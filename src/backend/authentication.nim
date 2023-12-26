## http_auth won't work :(

import jester/request
import std/[
    random, times, strutils, tables, selectors,
    options
]
import chronicles as log
import libsodium/[sodium, sodium_sizes]
import ../settings
import ./exceptions
import ./validation
import ../importDb

export options
export selectors
export sodium

type
    User* = object
        id*: int
        name*: string
        joinedOn*: Time
        lastLoggedIn*: Time

proc toSessId*(req: Request): string =
    ## Basically PHPSESSID's algorithm.
    var r = initRand()
    try:
        return "$# $# $#" % [
            req.ip, $(getTime().toUnixFloat()), $(r.next())
        ]
    except CatchableError as e:
        log.debug("Unable to generate session ID hash, using random number instead.", kind=e.name, emsg=e.msg)
        return $(r.next())

proc toHashed*(s: string): string =
    result = s.cryptoGenericHash(
        cryptoGenericHashBytes()
    ).toHex().toLower()

proc invalidateExpiredSessions*(): void =
    withSessionDb:
        let numDeletedSessions = sessDb.execAffectedRows(
        sql"Delete From sessions Where (expires < ? and expires != 0)",
            getTime().toUnix()
        )

        if numDeletedSessions > 0:
            log.debug "Deleted expired sessions", numSessions=numDeletedSessions

proc getSessionIdFrom*(req: Request): string =
    # get cookie parameter from the session
    let cookieParam = req.cookies.getOrDefault(sessionCookieName, "")

    withSessionDb:
        if sessDb.getValue(sql"Select sid From sessions Where sid = ?", cookieParam) == "": # session does not exist in table
            log.debug("No session cookie, generating a new one!")
            let newId = req.toSessId().toHashed()
            sessDb.exec(
                sql"Insert Into sessions(sid, expires) Values (?, ?)",
                newId,
                $((getTime() + defaultSessionExpirationTime).toUnix())
            )
            return newId
        else: # session exists
            return cookieParam

proc userFromRow(user: Row): User =
    return User(
        id: user[0].parseInt(),
        name: user[1],
        joinedOn: user[2].parseInt().fromUnix(),
        lastLoggedIn: user[3].parseInt().fromUnix()
    )

proc getCurrentUser*(sessId: string): Option[User]  =
    var userId: string

    withSessionDb:
        userId = sessDb.getValue(
            sql"Select user_id From sessions_users Where sid = ?",
            sessId
        )

        if userId == "":
            log.debug("No user attached to session", sessId=sessId)
            return none(User)

    withMainDb:
        let user = mainDb.getRow(
            sql"Select id, username, joined_on, logged_in From users Where id = ?",
            userId
        )

        if user == @[]:
            log.debug("User does not exist", userId=userId)
            return none(User)

        return some(userFromRow(user))

proc setNewAcsrfToken*(sessId: string): string  =
    # generate new ACSRF string
    let acsrfString = randombytes(16).toHex().toLower()

    withSessionDb:
        if sessDb.getValue(sql"Select sid From session_acsrf Where sid = ?", sessId) != sessId:
            log.debug("Inserted a new ACSRF token", sessId=sessId, acsrfString=acsrfString)
            sessDb.exec(sql"Insert Into session_acsrf(sid, token) Values (?, ?)", sessId, acsrfString)
        else:
            log.debug("Updated an ACSRF token", sessId=sessId, acsrfString=acsrfString)
            sessDb.exec(sql"Update session_acsrf Set token = ? Where sid = ?", acsrfString, sessId)
        return acsrfString

proc verifyAcsrfToken*(sessId: string, acsrfToken: string): void =
    withSessionDb:
        if sessDb.getValue(sql"Select 1 From session_acsrf Where sid = ? And token = ?", sessId, acsrfToken) != "1":
            raise newException(TokenException, "Please try again...")

        # Token used
        sessDb.exec(sql"Delete From session_acsrf Where sid = ? And token = ?", sessId, acsrfToken)

proc processSignUp*(req: Request): tuple[user: Option[User], password: string, errors: seq[ref Exception]]  =
    withMainDb:
        var errors: seq[ref Exception] = @[]
        let
            sessId = getSessionIdFrom(req)
        try:
            sessId.verifyAcsrfToken(req.params.getOrDefault(antiCsrfFieldName, ""))
        except TokenException as e:
            errors.add(e)
        var
            rqUsername = req.params.getOrDefault(usernameFieldName, "")
        let
            rqPassword = req.params.getOrDefault(passwordFieldName, "")
            rqConfirmPassword = req.params.getOrDefault(confirmPasswordFieldName, "")

        try:
            rqUsername = rqUsername.sanitizeUsername()
        except ValidationError:
            errors.add(
                newException(LoginException, "Invalid username!")
            )
        if rqUsername == "":
            errors.add(
                newException(LoginException, "Username missing!")
            )
        if mainDb.getValue(sql"Select 1 From users Where username = ?", rqUsername) == "1":
            errors.add(
                newException(LoginException, "Someone else already has that username!")
            )
        # add additional checks for username here
        if rqPassword == "":
            errors.add(
                newException(LoginException, "Password missing!")
            )
        if rqConfirmPassword == "" or (rqPassword != rqConfirmPassword):
            errors.add(
                newException(LoginException, "Passwords do not match!")
            )
        let user = if errors.len() != 0:
            none(User)
        else:
            some(
                User(
                name: rqUsername,
                joinedOn: getTime()
                )
            )
        return (user: user, password: rqPassword, errors: errors)

proc doSignUp*(user: User, pw: string): void  =
    withMainDb:
        let pwHashed = cryptoPwHashStr(pw)

        log.debug("Someone has signed up", userName=user.name)

        let userId = mainDb.tryInsertID(sql"""
            Insert Into users(username, password, joined_on)
            Values (?, ?, ?)
        """, user.name, pwHashed, user.joinedOn.toUnix())

        if userId != -1: # add blacklist
            mainDb.exec(sql"""
                Insert Into user_blacklists(user_id) Values (?)
            """, userId)

proc processLogIn*(req: Request): tuple[
    user: Option[User],
    errors: seq[ref Exception],
    alreadyLoggedIn: bool,
    dontAutoLogOut: bool
] =
    const genericUnameOrPwInvalidMsg = "Username or password invalid"

    let existingUser = getSessionIdFrom(req).getCurrentUser()
    if existingUser.isSome():
        log.debug("User already logged in", user=existingUser.get().name)
        # skip the login process
        return (
            user: existingUser,
            errors: @[],
            alreadyLoggedIn: true,
            dontAutoLogOut: true
        )

    var errors: seq[ref Exception] = @[]
    let
        sessId = getSessionIdFrom(req)
    try:
        sessId.verifyAcsrfToken(req.params.getOrDefault(antiCsrfFieldName, ""))
    except TokenException as e:
        errors.add(e)

    var
        uname = req.params.getOrDefault(usernameFieldName, "")
        pw = req.params.getOrDefault(passwordFieldName, "")
        remember = req.params.getOrDefault(rememberFieldName, "")

    withMainDb:
        let userData = mainDb.getRow(
            sql"Select id, username, joined_on, logged_in, password From users Where username = ?",
            uname
        )

        block validate:
            try:
                uname = uname.sanitizeUsername()
            except ValidationError:
                log.debug("Invalid username", name=uname)
                errors.add(newException(LoginException, genericUnameOrPwInvalidMsg))
                break validate
            if userData[0] == "":
                log.debug("Username not found", name=uname)
                errors.add(newException(LoginException, genericUnameOrPwInvalidMsg))
            else:
                # user in db
                if not cryptoPwHashStrVerify(userData[4], pw):
                    log.debug("Password incorrect", name=uname)
                    errors.add(newException(LoginException, genericUnameOrPwInvalidMsg))

        let user = if errors.len() == 0:
            some(userFromRow(userData))
        else:
            none(User)

        return (
            user: user,
            errors: errors,
            alreadyLoggedIn: false,
            dontAutoLogOut: (remember.strip() != "")
        )

proc doLogIn*(sessId: string, user: User, dontAutoLogOut: bool): void =
    withSessionDb:
        # check if session is valid
        if sessDb.getValue(
            sql"Select 1 From sessions Where sid = ?", sessId
        ) != "1":
            log.debug("Someone's trying to log in but their session expired...")
            return

        sessDb.exec(
            sql"Insert Into sessions_users(sid, user_id) Values (?, ?)",
            sessId, user.id
        )
        log.debug("Someone has logged in", sessId=sessId, userName=user.name)

        if dontAutoLogOut:
            sessDb.exec(
                sql"Update sessions Set expires = 0 Where sid = ?",
                sessId
            )
            log.debug("Requested persistent session", sessId=sessId, userName=user.name)

        withMainDb:
            mainDb.exec(
                sql"Update users Set logged_in = ? Where id = ?",
                getTime().toUnix(),
                user.id
            )

proc logOut*(sessId: string): void =
    ## Simply deletes the session, as that'll delete everything under it too
    withSessionDb:
        log.debug("A user logged out", sessId=sessId)

        sessDb.exec(sql"""Delete From sessions Where sid = ?""", sessId)
