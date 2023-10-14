import std/[tables, times]

const
    siteName* = "toybooru"
    siteRevDate* = staticExec("git show -s --format='%cd' --date=format:'%Y-%m-%d'")
    siteRevHash* = staticExec("git show -s --format='%h'")

# relative to site
    imgSuffix* = "/images"
    thumbSuffix* = "/thumbs"

# relative to source dir
    pubDir* = "./public"
    imgDir* = pubDir & imgSuffix
    thumbDir* = pubDir & thumbSuffix

# db files also relative to source dir
    dbFile* = "main.db"
    sessionDbFile* = "session.db"

# parameters
    thumbSize* = 250 # width or height, whichever's greater
    defaultNumResults* = 25

# link to source code
    sourceLink* = "https://github.com/ZoomTen/toybooru"

# authentication stuffs
    sessionCookieName* = "TOYBOORU_SESSION"
    usernameFieldName* = "usn"
    passwordFieldName* = "pw"
    rememberFieldName* = "rmm"
    confirmPasswordFieldName* = "cfpw"
    antiCsrfFieldName* = "acsrf"

# config stuffs
    blacklistFieldName* = "bls"

    defaultBlacklist* = "rating:questionable rating:explicit"

proc makeMimeMappings*(): Table[string, string] =
    return {
        "image/jpeg": "jpg",
        "image/png": "png",
        "video/mp4": "mp4"
    }.toTable

let
    defaultSessionExpirationTime* = 30.minutes()
