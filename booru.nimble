# Package

version       = "0.1.0"
author        = "Zumi Daxuya"
description   = "Booru-like web engine"
license       = "MIT"
srcDir        = "src"
bin           = @["booru", "importFromHydrus"]


# Dependencies

requires "nim 1.6.14..<2.0.0"

# Server dependencies

requires [
    "jester#185c610",
    "karax#2371ea3",
    "stbimage#ba5f4528",
    "regex#199e696"
]

# Debug dependencies

requires [
    "chronicles#1922045"
]

task cleanDb, "Clean database and image files":
    rmDir("public/images")
    rmDir("public/thumbs")
    rmFile("main.db")
    echo("Go to localhost:5000/ upon restarting the server to re-init the booru.")

task clean, "Clean generated files":
    for binName in bin:
        rmFile(binName)
        rmFile(binName & ".exe")

task start, "Run server":
    exec("nimble run booru")
