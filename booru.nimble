# Package

version       = "0.1.0"
author        = "Zumi Daxuya"
description   = "Booru-like web engine"
license       = "MIT"
srcDir        = "src"
bin           = @["booru", "importFromHydrus"]


# Dependencies

requires "nim >= 1.6.14"

# Server dependencies

requires [
    "jester#185c610",
    "karax#2371ea3",
    "stbimage#ba5f4528",
    "regex#199e696"
]

if NimMajor > 1:
    requires "db_connector#e656937"
    requires "checksums#025bcca"

# Debug dependencies

requires [
    "chronicles#1922045"
]

# Authentication dependencies

requires [
    "libsodium#881f3ae"
]

task cleanDb, "Clean database and image files":
    rmDir("public/images")
    rmDir("public/thumbs")
    rmFile("main.db")
    rmFile("session.db")
    echo("Go to localhost:5000/ upon restarting the server to re-init the booru.")

task clean, "Clean generated files":
    for binName in bin:
        rmFile(binName)
        rmFile(binName & ".exe")

task start, "Run server":
    exec("nimble -d:chronicles_disabled_topics:\"stdlib\" --threads:off run booru")
