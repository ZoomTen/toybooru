import jester/request
from ./authentication import User
import std/[
    strutils, tables
]
import ../settings
import chronicles as log

import std/db_sqlite

{.push raises:[].}

proc getBlacklistConfig*(user: User): string {.raises:[DbError].}=
    ## Fetches the raw blacklist config straight from the DB
    let db = open(dbFile, "", "", "")
    defer: db.close()

    return db.getValue(
        sql"Select blacklist From user_blacklists Where user_id = ?",
        $(user.id)
    ).strip()

proc setBlacklistConfig*(user: User, blklist: string) {.raises:[DbError].} =
    ## Sets raw blacklist config
    let db = open(dbFile, "", "", "")
    defer: db.close()

    db.exec(
        sql"Update user_blacklists Set blacklist = ? Where user_id = ?",
        blklist, $(user.id)
    )

proc processSetBlacklistConfig*(user: User, rq: Request) {.raises:[Exception].}=
    log.logScope:
        topics = "processSetBlacklistConfig"
    let newBlacklist = rq.params.getOrDefault(blacklistFieldName, "")
    user.setBlacklistConfig(newBlacklist.strip())
    log.debug("Set blacklist", userName=user.name, newBlacklist=newBlacklist)
