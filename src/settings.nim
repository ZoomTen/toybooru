import std/[tables, times]

const
    siteName* = "toybooru"

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
    confirmPasswordFieldName* = "cfpw"
    antiCsrfFieldName* = "acsrf"


let
    mimeMappings* = {
        "image/jpeg": "jpg",
        "image/png": "png",
        "video/mp4": "mp4"
    }.toTable
    defaultSessionExpirationTime* = 30.minutes()
