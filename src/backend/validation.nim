import std/[
    strutils
]
import regex

{.push raises:[].}

type
    ValidationError* = object of ValueError

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
        ([a-z_]+:)?      # can have a category, limited charset
        [a-z0_9<>!\(\)]+ # supported characters
    """
proc normalizeSpaces(s: string): string {.raises: [ValueError].} =
    return s.replace(re2"\s+", " ")

proc sanitizeQuery*(s: string): string {.raises: [ValueError].} =
    result = s.strip().normalizeSpaces()
    if not match(result, QuerySyntax):
        raise newException(ValidationError, "Invalid query!")
    return result

proc sanitizeKeyword*(s: string): string {.raises: [ValidationError].} =
    result = s.strip()
    if not match(result, KeywordSyntax):
        raise newException(ValidationError, "Invalid keyword!")
    return result
