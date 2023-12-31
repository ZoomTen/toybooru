import jester/request
import std/tables

import results
export results

{.push raises:[].}

proc getParamOrDefault*(
    r: Request; key, default: string
): string {.inline.} =
    try:
        return r.params.getOrDefault(key, default)
    except Exception:
        return default

proc getCookieOrDefault*(
    r: Request; key, default: string
): string {.inline.} =
    try:
        return r.cookies.getOrDefault(key, default)
    except Exception:
        return default
