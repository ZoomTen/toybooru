import jester/request
from ./authentication import User
import std/[
    strutils, tables
]
import ../settings
import chronicles as log
import ../importDb

proc getBlacklistConfig*(user: User): string =
    ## Fetches the raw blacklist config straight from the DB
    withMainDb:
        return mainDb.getValue(
            sql"Select blacklist From user_blacklists Where user_id = ?",
            $(user.id)
        ).strip()

proc setBlacklistConfig*(user: User, blklist: string)  =
    ## Sets raw blacklist config
    withMainDb:
        mainDb.exec(
            sql"Update user_blacklists Set blacklist = ? Where user_id = ?",
            blklist, $(user.id)
        )

proc processSetBlacklistConfig*(user: User, rq: Request) =
    log.logScope:
        topics = "processSetBlacklistConfig"
    let newBlacklist = rq.params.getOrDefault(blacklistFieldName, "")
    user.setBlacklistConfig(newBlacklist.strip())
    log.debug("Set blacklist", userName=user.name, newBlacklist=newBlacklist)
