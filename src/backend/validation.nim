import std/[
    strutils
]
import regex
import ./exceptions

import results
export results

{.push raises:[].}

const
    QuerySyntax = re2"""(?x)
        (
            -?                      # can be negated
            ([a-z_]+:)?             # can have a category, limited characterset
            [a-z_0-9<>!\(\)]+       # tag syntax
            \s*                     # separated by spaces
        )+ # take multiple copies
    """
    KeywordSyntax = re2"""(?x)
        ([a-z_]+:)?       # can have a category, limited charset
        [a-z0-9_<>!\(\)]+ # supported characters
    """

    UsernameSyntax = re2"""(?x)
        ([a-zA-Z_0-9]){1,15}
    """
proc normalizeSpaces*(s: string): Result[string, string] =
    try:
        return s.replace(re2"\s+", " ").ok()
    except ValueError as e:
        return err(e.msg)

proc sanitizeQuery*(s: string): Result[string, string]  =
    let res = ?s.strip().normalizeSpaces()
    if not match(res, QuerySyntax):
        return err("Invalid query!")
    return res.ok()

proc sanitizeKeyword*(s: string): Result[string, string]  =
    let res = s.strip()
    if not match(res, KeywordSyntax):
        return err("Invalid keyword: " & s)
    return res.ok()

proc sanitizeUsername*(s: string): Result[string, string]  =
    let res = s.strip()
    if res == "":
        return err("Missing username")
    if not match(res, UsernameSyntax):
        return err("Invalid username: " & s)
    return res.ok()

proc sanitizeBlacklist*(s: string): Result[string, string]  =
    ## Turns it into a query that can be appended to an existing query behind the scenes
    let normBlacklist = ?s.strip().normalizeSpaces()
    var blacklistStuffs: seq[string] = @[]
    for tag in normBlacklist.split(" "):
        try:
            blacklistStuffs.add("-" & ?sanitizeKeyword(tag))
        except ValidationError:
            discard
    return blacklistStuffs.join(" ").ok()
