import jester/request
from ./authentication import User
import std/strutils
import ../settings
import chronicles as log
import ../importDb
import ../helpers/getParams

{.push raises: [].}

proc getBlacklistConfig*(user: User): Result[string, string] =
    ## Fetches the raw blacklist config straight from the DB
    withMainDb:
        return mainDb.getValue(
            sql"Select blacklist From user_blacklists Where user_id = ?",
            $(user.id)
        ).strip().ok()

proc setBlacklistConfig*(user: User, blklist: string): Result[void, string]  =
    ## Sets raw blacklist config
    withMainDb:
        mainDb.exec(
            sql"Update user_blacklists Set blacklist = ? Where user_id = ?",
            blklist, $(user.id)
        )
    return ok()

proc processSetBlacklistConfig*(user: User, rq: Request): Result[void, string] =
    let newBlacklist = rq.getParamOrDefault(blacklistFieldName, "")
    ?user.setBlacklistConfig(newBlacklist.strip())
    log.debug("Set blacklist", userName=user.name, newBlacklist=newBlacklist)
