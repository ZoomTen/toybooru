import std/tables

const
    siteName* = "toybooru"

# relative to site
    imgSuffix* = "/images"
    thumbSuffix* = "/thumbs"

# relative to source dir
    pubDir* = "./public"
    imgDir* = pubDir & imgSuffix
    thumbDir* = pubDir & thumbSuffix
    dbFile* = "main.db"

    thumbSize* = 250 # width or height, whichever's greater
    defaultNumResults* = 25

let mimeMappings* = {
        "image/jpeg": "jpg",
        "image/png": "png",
        "video/mp4": "mp4"
    }.toTable
