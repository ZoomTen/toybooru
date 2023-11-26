import jester
import chronicles as log
import std/strutils
import ../settings
import ../backend/authentication as auth
import ../backend/validation as validate
import ../backend/userConfig as config
import ../importDb

type
    PageVars* = tuple
        query: string ## final query
        originalQuery: string ## contains raw query!
        pageNum: int
        numResults: int
        distance: int

proc getVarsFromParams*(params: Table, user: Option[auth.User]): PageVars =
    log.logScope:
        topics = "getVarsFromParams"

    let blacklistDef = if user.isNone():
        try:
            log.debug("Default blacklist set",
                    blacklist=defaultBlacklist
            )
            validate.sanitizeBlacklist(defaultBlacklist)
        except ValueError:
            ""
    else:
        try:
            let blist = config.getBlacklistConfig(user.get())
            log.debug("Custom blacklist set",
                    blacklist=blist
            )
            validate.sanitizeBlacklist(blist)
        except DbError:
            ""
        except ValueError:
            ""

    log.debug("Converted blacklist to query to be appended", blacklistDef=blacklistDef)

    result.query = params.getOrDefault("q", "")

    result.originalQuery = result.query

    result.query = result.query & " " & blacklistDef

    result.distance = try: # Hamming distance
            params.getOrDefault("distance", "8").parseInt()
        except ValueError: 8

    result.pageNum = try:
            params.getOrDefault("page", "0").parseInt()
        except ValueError: 0
    result.numResults = try:
            params.getOrDefault("count", $defaultNumResults).parseInt()
        except ValueError: defaultNumResults
