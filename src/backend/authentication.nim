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

when NimMajor > 1:
    import db_connector/db_sqlite
else:
    import std/db_sqlite

export options
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
    log.logScope:
        topics = "toSessId"

    var r = initRand()
    try:
        return "$# $# $#" % [
            req.ip, $(getTime().toUnixFloat()), $(r.next())
        ]
    except CatchableError as e:
        log.debug("Unable to generate session ID hash, using random number instead.", kind=e.name, emsg=e.msg)
        return $(r.next())

proc toHashed*(s: string): string {.raises: [SodiumError, ValueError].}=
    result = s.cryptoGenericHash(
        cryptoGenericHashBytes()
    ).toHex().toLower()

proc invalidateExpiredSessions*() {.raises:[DbError].} =
    log.logScope:
        topics = "invalidateExpiredSessions"

    let sessDb = open(sessionDbFile, "", "", "")
    sessDb.exec(sql"PRAGMA foreign_keys = ON") # needed for cascade
    defer: sessDb.close()

    let numDeletedSessions = sessDb.execAffectedRows(
    sql"Delete From sessions Where (expires < ? and expires != 0)",
        getTime().toUnix()
    )

    if numDeletedSessions > 0:
        log.debug "Deleted expired sessions", numSessions=numDeletedSessions

proc getSessionIdFrom*(req: Request): string {.raises: [DbError, IOSelectorsException, KeyError, SodiumError, ValueError].} =
    log.logScope:
        topics = "getSessionIdFrom"

    let sessDb = open(sessionDbFile, "", "", "")
    sessDb.exec(sql"PRAGMA foreign_keys = ON") # needed for cascade
    defer: sessDb.close()

    # get cookie parameter from the session
    let cookieParam = req.cookies.getOrDefault(sessionCookieName, "")

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

proc userFromRow(user: Row): User {.raises:[ValueError].}=
    return User(
        id: user[0].parseInt(),
        name: user[1],
        joinedOn: user[2].parseInt().fromUnix(),
        lastLoggedIn: user[3].parseInt().fromUnix()
    )

proc getCurrentUser*(sessId: string): Option[User] {.raises: [DbError, ValueError].} =
    log.logScope:
        topics = "getCurrentUser"

    let
        sessDb = open(sessionDbFile, "", "", "")
        mainDb = open(dbFile, "", "", "")
    defer:
        sessDb.close()
        mainDb.close()
    sessDb.exec(sql"PRAGMA foreign_keys = ON")

    let userId = sessDb.getValue(
        sql"Select user_id From session_user Where sid = ?",
        sessId
    )

    if userId == "":
        log.debug("No user attached to session", sessId=sessId)
        return none(User)

    let user = mainDb.getRow(
        sql"Select id, username, joined_on, logged_in From users Where id = ?",
        userId
    )

    if user == @[]:
        log.debug("User does not exist", userId=userId)
        return none(User)

    return some(userFromRow(user))

proc setNewAcsrfToken*(sessId: string): string {.raises: [DbError].} =
    log.logScope:
        topics = "setNewAcsrfToken"

    let sessDb = open(sessionDbFile, "", "", "")
    defer: sessDb.close()
    sessDb.exec(sql"PRAGMA foreign_keys = ON")

    # generate new ACSRF string
    let acsrfString = randombytes(16).toHex().toLower()

    if sessDb.getValue(sql"Select sid From session_acsrf Where sid = ?", sessId) != sessId:
        log.debug("Inserted a new ACSRF token", sessId=sessId, acsrfString=acsrfString)
        sessDb.exec(sql"Insert Into session_acsrf(sid, token) Values (?, ?)", sessId, acsrfString)
    else:
        log.debug("Updated an ACSRF token", sessId=sessId, acsrfString=acsrfString)
        sessDb.exec(sql"Update session_acsrf Set token = ? Where sid = ?", acsrfString, sessId)
    return acsrfString

proc verifyAcsrfToken*(sessId: string, acsrfToken: string) {.raises: [DbError, TokenException].} =
    let sessDb = open(sessionDbFile, "", "", "")
    defer: sessDb.close()
    sessDb.exec(sql"PRAGMA foreign_keys = ON")

    if sessDb.getValue(sql"""Select 1 From session_acsrf Where sid = ? And token = ?""", sessId, acsrfToken) != "1":
        raise newException(TokenException, "Please try again...")

proc processSignUp*(req: Request): tuple[user: Option[User], password: string, errors: seq[ref Exception]] {.raises: [DbError, IOSelectorsException, KeyError, SodiumError, ValueError, Exception].} =
    let mainDb = open(dbFile, "", "", "")
    defer: mainDb.close()

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

proc doSignUp*(user: User, pw: string) {.raises: [DbError, SodiumError, ValueError].} =
    let mainDb = open(dbFile, "", "", "")
    defer: mainDb.close()

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

proc processLogIn*(req: Request): tuple[user: Option[User], errors: seq[ref Exception], alreadyLoggedIn: bool] {.raises: [DbError, ValueError, IOSelectorsException, SodiumError, Exception].}=
    log.logScope:
        topics = "processLogIn"

    const genericUnameOrPwInvalidMsg = "Username or password invalid"

    let existingUser = getSessionIdFrom(req).getCurrentUser()
    if existingUser.isSome():
        log.debug("User already logged in", user=existingUser.get().name)
        # skip the login process
        return (user: existingUser, errors: @[], alreadyLoggedIn: true)

    let
        sessionDb = open(sessionDbFile, "", "", "")
        userDb = open(dbFile, "", "", "")
    defer:
        sessionDb.close()
        userDb.close()
    sessionDb.exec(sql"PRAGMA foreign_keys = ON")

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

    let userData = userDb.getRow(sql"Select id, username, joined_on, logged_in, password From users Where username = ?", uname)

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
        alreadyLoggedIn: false
    )

proc doLogIn*(sessId: string, user: User) {.raises: [DbError].}=
    log.logScope:
        topics = "doLogIn"

    let
        sessionDb = open(sessionDbFile, "", "", "")
        userDb = open(dbFile, "", "", "")
    defer:
        sessionDb.close()
        userDb.close()
    sessionDb.exec(sql"PRAGMA foreign_keys = ON")

    # check if session is valid
    if sessionDb.getValue(
        sql"Select 1 From sessions Where sid = ?", sessId
    ) != "1":
        log.debug("Someone's trying to log in but their session expired...")
        return

    sessionDb.exec(
        sql"Insert Into session_user(sid, user_id) Values (?, ?)",
        sessId, user.id
    )
    log.debug("Someone has logged in", sessId=sessId, userName=user.name)

    userDb.exec(
        sql"Update users Set logged_in = ? Where id = ?",
        getTime().toUnix(),
        user.id
    )

proc logOut*(sessId: string) {.raises: [DbError].}=
    ## Simply deletes the session, as that'll delete everything under it too
    let sessionDb = open(sessionDbFile, "", "", "")
    sessionDb.exec(sql"PRAGMA foreign_keys = ON")
    defer: sessionDb.close()

    log.debug("A user logged out", sessId=sessId)

    sessionDb.exec(sql"""Delete From sessions Where sid = ?""", sessId)
