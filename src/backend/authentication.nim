## http_auth won't work :(

import jester/request
import std/[
    random, times, strutils, selectors
]
import chronicles as log
import libsodium/[sodium, sodium_sizes]
import ../settings
import ./validation
import ../importDb
import results
import ../helpers/getParams
import ../helpers/catchErrMsg

export results
export selectors
export sodium

{.push raises: [].}

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
    let hashVal = catchErrMsg:
        s.cryptoGenericHash(cryptoGenericHashBytes())
        .toHex()
        .toLower()
    return hashVal.expect("hash value must exist")

proc invalidateExpiredSessions*(): Result[void, string] =
    withSessionDb:
        let numDeletedSessions = sessDb.execAffectedRows(
        sql"Delete From sessions Where (expires < ? and expires != 0)",
            getTime().toUnix()
        )

        if numDeletedSessions > 0:
            log.debug "Deleted expired sessions", numSessions=numDeletedSessions
    return ok()

proc getSessionIdFrom*(req: Request): Result[string, string] =
    # get cookie parameter from the session
    let cookieParam = req.getCookieOrDefault(sessionCookieName, "")

    withSessionDb:
        if sessDb.getValue(
            sql"Select sid From sessions Where sid = ?",
            cookieParam
        ) == "": # session does not exist in table
            log.debug("No session cookie, generating a new one!")

            let newId = req.toSessId().toHashed()
            sessDb.exec(
                sql"Insert Into sessions(sid, expires) Values (?, ?)",
                newId,
                $((getTime() + defaultSessionExpirationTime).toUnix())
            )

            return newId.ok()
        else: # session exists
            return cookieParam.ok()

proc userFromRow(user: Row): Result[User, string] =
    var
        userId: int
        joinedTimestamp: Time
        lastLoggedTimestamp: Time

    try: userId = user[0].parseInt()
    except ValueError: return err("ID invalid")

    try: joinedTimestamp = user[2].parseInt().fromUnix()
    except ValueError: return err("Join timestamp invalid")

    try: lastLoggedTimestamp = user[3].parseInt().fromUnix()
    except ValueError: return err("Last logged in timestamp invalid")

    return User(
        id: userId,
        name: user[1],
        joinedOn: joinedTimestamp,
        lastLoggedIn: lastLoggedTimestamp
    ).ok()

proc getCurrentUser*(sessId: string): Result[User, string]  =
    var userId: string

    withSessionDb:
        userId = sessDb.getValue(
            sql"Select user_id From sessions_users Where sid = ?",
            sessId
        )

        if userId == "":
            return err("No user attached to session " & sessId)

    withMainDb:
        let user = mainDb.getRow(
            sql"Select id, username, joined_on, logged_in From users Where id = ?",
            userId
        )

        if user == @[]:
            return err("User " & userId & "does not exist")

        return userFromRow(user)

proc setNewAcsrfToken*(sessId: string): Result[string, string]  =
    # generate new ACSRF string
    let acsrfString = randombytes(16).toHex().toLower()

    withSessionDb:
        if sessDb.getValue(
            sql"Select sid From session_acsrf Where sid = ?",
            sessId
        ) != sessId:
            log.debug("Inserted a new ACSRF token", sessId=sessId, acsrfString=acsrfString)
            sessDb.exec(sql"Insert Into session_acsrf(sid, token) Values (?, ?)", sessId, acsrfString)

        else:
            log.debug("Updated an ACSRF token", sessId=sessId, acsrfString=acsrfString)
            sessDb.exec(sql"Update session_acsrf Set token = ? Where sid = ?", acsrfString, sessId)

    return acsrfString.ok()

proc verifyAcsrfToken*(sessId: string, acsrfToken: string): Result[void, string] =
    withSessionDb:
        if sessDb.getValue(
            sql"Select 1 From session_acsrf Where sid = ? And token = ?",
            sessId,
            acsrfToken
        ) != "1":
            return err("Please try again...")

        # Token used
        sessDb.exec(sql"Delete From session_acsrf Where sid = ? And token = ?", sessId, acsrfToken)
    return ok()

proc userExists*(username: string): Result[bool, string] =
    withMainDb:
        return (mainDb.getValue(
            sql"Select 1 From users Where username = ?",
            username
        ) == "1").ok()

proc verifySession(req: Request): Result[void, string] =
    let sessId = ?getSessionIdFrom(req)
    ?verifyAcsrfToken(
        sessId,
        req.getParamOrDefault(antiCsrfFieldName, "")
    )
    return ok()

proc processSignUp*(req: Request): Result[User, seq[string]]  =
    var errors: seq[string] = @[]

    var
        rqUsername = req.getParamOrDefault(usernameFieldName, "")

    let
        rqPassword = req.getParamOrDefault(passwordFieldName, "")
        rqConfirmPassword = req.getParamOrDefault(confirmPasswordFieldName, "")

    block sessionValidation: # returns immediately
        if (
            let sessVerified = req.verifySession()
            sessVerified.isErr
        ):
            errors.add(sessVerified.error())
            return err(errors)

    block usernameValidation:
        let usernameValid = rqUsername.sanitizeUsername()
        if usernameValid.isErr: errors.add(usernameValid.error)

        rqUsername = usernameValid.value

        if (
            # can't use withMainDb here :(
            let usernameExists = rqUsername.userExists()
            usernameExists.isOk and usernameExists.value
        ):
            errors.add("Someone else already has that username!")

    block passwordValidation:
        if rqPassword == "": errors.add("Password missing!")
        if rqConfirmPassword != rqPassword: errors.add("Passwords do not match!")

    if errors.len > 0: return err(errors)

    return User(name: rqUsername, joinedOn: getTime()).ok()

proc doSignUp*(user: User, pw: string): Result[void, string]  =
    withMainDb:
        var pwHashed: string

        try:
            pwHashed = cryptoPwHashStr(pw)
        except Exception: return err("Error hashing password")

        log.debug("Someone has signed up", userName=user.name)

        let userId = mainDb.tryInsertID(sql"""
            Insert Into users(username, password, joined_on)
            Values (?, ?, ?)
        """, user.name, pwHashed, user.joinedOn.toUnix())

        if userId != -1: # add blacklist
            mainDb.exec(sql"""
                Insert Into user_blacklists(user_id) Values (?)
            """, userId)
    return ok()

proc processLogIn*(req: Request): Result[tuple[user: User, dontAutoLogOut: bool], string] =
    const genericUnameOrPwInvalidMsg = "Username or password invalid"
    var
        rqUsername = req.getParamOrDefault(usernameFieldName, "")
        rqPassword = req.getParamOrDefault(passwordFieldName, "")
        rqRemember = req.getParamOrDefault(rememberFieldName, "")
        userData: Row

    # TODO: handle "user logged in" in caller for processLogin

    block sessionValidation: # returns immediately
        if (
            let sessVerified = req.verifySession()
            sessVerified.isErr
        ):
            log.debug("Session verification error", error=sessVerified.error())
            return err(genericUnameOrPwInvalidMsg)

    block userValidation:
        let usernameValid = rqUsername.sanitizeUsername()
        if usernameValid.isErr:
            log.debug("Username validation error", error=usernameValid.error())
            return err(genericUnameOrPwInvalidMsg)

        rqUsername = usernameValid.value

        let usernameExists = rqUsername.userExists()

        if usernameExists.isErr:
            log.debug("Username validation error", error=usernameExists.error())
            return err(genericUnameOrPwInvalidMsg)

        if not usernameExists.value:
            log.debug("User does not exist", name=rqUsername)
            return err(genericUnameOrPwInvalidMsg)

    block passwordValidation:
        withMainDb:
            userData = mainDb.getRow(
                sql"Select id, username, joined_on, logged_in, password From users Where username = ?",
                rqUsername
            )
            if not cryptoPwHashStrVerify(userData[4], rqPassword):
                log.debug("Password incorrect", name=rqUsername)
                return err(genericUnameOrPwInvalidMsg)

    return ok(
        (
            user: ?userFromRow(userData),
            dontAutoLogOut: rqRemember.strip() != ""
        )
    )

proc doLogIn*(sessId: string, user: User, dontAutoLogOut: bool): Result[void, string] =
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

proc logOut*(sessId: string): Result[void, string] =
    ## Simply deletes the session, as that'll delete everything under it too
    withSessionDb:
        log.debug("A user logged out", sessId=sessId)
        sessDb.exec(sql"""Delete From sessions Where sid = ?""", sessId)
