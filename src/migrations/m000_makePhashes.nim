import ../backend/setup as setup
import ../backend/upload as upload
import std/[
    os, mimetypes, strutils, sugar, tables
]
import ../settings
import ../backend/pHashes as phash
import chronicles as log

when NimMajor > 1:
    import db_connector/db_sqlite
else:
    import std/db_sqlite

{.push raises: [].}

when isMainModule:
    var args = commandLineParams()
    if args.len == 1:
        setup.imageTable()
        setup.imagePhashesTable()

        let db = open(dbFile, "", "", "")
        defer: db.close()

        let mimeMappings = makeMimeMappings()

        for row in db.instantRows(
            sql"""
                Select id, hash, format From images
            """
        ):
            let
                id = row[0]
                hash = row[1]
                extension = mimeMappings[row[2]]
                file = imgDir & "/" & hash & "." & extension
            if not (extension in ["mp4"]):
                log.info(
                    "Processing image",
                    id = id,
                    file = file
                )
                let phash = phash.pHash(file.readFile())
                db.exec(sql"""
                    Insert Into image_phashes (image_id, phash) Values (?, ?)
                """, id, phash)
                log.info(
                    "Success",
                    pHash = phash
                )


    else:
        debugEcho "Usage: ./m000_makePhashes <anything>"
        debugEcho ""
        debugEcho "<anything> is for confirmation only"
