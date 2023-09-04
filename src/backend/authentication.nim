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

import std/db_sqlite

export options

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
        getTime().toUnix
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
        raise newException(TokenException, "Invalid token")

proc processSignUp*(req: Request): tuple[user: Option[User], password: string, errors: seq[ref Exception]] {.raises: [DbError, IOSelectorsException, KeyError, SodiumError, ValueError, Exception].} =
    var errors: seq[ref Exception] = @[]
    let
        sessId = getSessionIdFrom(req)
    try:
        sessId.verifyAcsrfToken(req.params.getOrDefault(antiCsrfFieldName, ""))
    except TokenException as e:
        errors.add(e)
    let
        # TODO: validate username
        rqUsername = req.params.getOrDefault(usernameFieldName, "").strip()
        rqPassword = req.params.getOrDefault(passwordFieldName, "")
        rqConfirmPassword = req.params.getOrDefault(confirmPasswordFieldName, "")
    if rqUsername == "":
        errors.add(
            newException(LoginException, "Username missing!")
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
    let user = if errors.len() > 0:
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

    mainDb.exec(sql"""
        Insert Into users(username, password, joined_on)
        Values (?, ?, ?)
    """, user.name, pwHashed, user.joinedOn.toUnix())

proc processLogIn*(req: Request): tuple[user: Option[User], errors: seq[ref Exception]] {.raises: [DbError, ValueError, IOSelectorsException, SodiumError, Exception].}=
    let isUser = getSessionIdFrom(req).getCurrentUser()
    if isUser.isSome():
        # skip the login process
        return (user: isUser, errors: @[])

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

    let
        # TODO: validate username
        uname = req.params.getOrDefault(usernameFieldName, "").strip()
        pw = req.params.getOrDefault(passwordFieldName, "")

    let user = userDb.getRow(sql"Select * From users Where username = ?", uname)

    if user == @[]:
        errors.add(newException(LoginException, "Username or password invalid"))
    else:
        # user in db
        if not cryptoPwHashStrVerify(user[2], pw):
            errors.add(newException(LoginException, "Username or password invalid"))

    if user == @[]:
        return (
            user: none(User),
            errors: errors
        )
    else:
        return (
            user: some(userFromRow(user)),
            errors: errors
        )

proc doLogin*(sessId: string, user: User) {.raises: [DbError].}=
    log.logScope:
        topics = "doLogin"

    let
        sessionDb = open(sessionDbFile, "", "", "")
        userDb = open(dbFile, "", "", "")
    defer:
        sessionDb.close()
        userDb.close()
    sessionDb.exec(sql"PRAGMA foreign_keys = ON")

    sessionDb.exec(
        sql"Insert Into session_user(sid, user_id) Values (?, ?)",
        sessId, user.id
    )
    log.debug("Associated a session with one user", sessId=sessId, userName=user.name)

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

    sessionDb.exec(sql"""Delete From sessions Where sid = ?""", sessId)