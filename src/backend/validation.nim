import std/[
    strutils
]
import regex
import ./exceptions

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
proc normalizeSpaces*(s: string): string {.raises: [ValueError].} =
    return s.replace(re2"\s+", " ")

proc sanitizeQuery*(s: string): string {.raises: [ValueError, ValidationError].} =
    result = s.strip().normalizeSpaces()
    if not match(result, QuerySyntax):
        raise newException(ValidationError, "Invalid query!")
    return result

proc sanitizeKeyword*(s: string): string {.raises: [ValidationError].} =
    result = s.strip()
    if not match(result, KeywordSyntax):
        raise newException(ValidationError, "Invalid keyword: " & s)
    return result

proc sanitizeUsername*(s: string): string {.raises: [ValidationError].} =
    result = s.strip()
    if not match(result, UsernameSyntax):
        raise newException(ValidationError, "Invalid username: " & s)
    return result

proc sanitizeBlacklist*(s: string): string {.raises: [ValueError].} =
    ## Turns it into a query that can be appended to an existing query behind the scenes
    let normBlacklist = s.strip().normalizeSpaces()
    var blacklistStuffs: seq[string] = @[]
    for tag in normBlacklist.split(" "):
        try:
            blacklistStuffs.add("-" & sanitizeKeyword(tag))
        except ValidationError:
            discard
    return blacklistStuffs.join(" ")
