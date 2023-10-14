import jester/request
from ./authentication import User
import std/[
    strutils, tables
]
import ../settings
import chronicles as log

when NimMajor > 1:
    import db_connector/db_sqlite
else:
    import std/db_sqlite

proc getBlacklistConfig*(user: User): string =
    ## Fetches the raw blacklist config straight from the DB
    let db = open(dbFile, "", "", "")
    defer: db.close()

    return db.getValue(
        sql"Select blacklist From user_blacklists Where user_id = ?",
        $(user.id)
    ).strip()

proc setBlacklistConfig*(user: User, blklist: string)  =
    ## Sets raw blacklist config
    let db = open(dbFile, "", "", "")
    defer: db.close()

    db.exec(
        sql"Update user_blacklists Set blacklist = ? Where user_id = ?",
        blklist, $(user.id)
    )

proc processSetBlacklistConfig*(user: User, rq: Request) =
    log.logScope:
        topics = "processSetBlacklistConfig"
    let newBlacklist = rq.params.getOrDefault(blacklistFieldName, "")
    user.setBlacklistConfig(newBlacklist.strip())
    log.debug("Set blacklist", userName=user.name, newBlacklist=newBlacklist)
