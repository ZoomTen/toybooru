import std/os
import ../settings

# db stuff, change for 2.0.0
import std/db_sqlite

import chronicles as log

{.push raises:[].}

proc folders*() {.raises: [OSError, IOError].}=
    log.logScope:
        topics = "setup.folders"

    # setup image bins
    for dir in [imgDir, thumbDir]:
        log.info("Created image folder", dir=dir)
        createDir(dir)

proc imageTable*() {.raises: [DbError].}=
    log.logScope:
        topics = "setup.imageTable"

    # setup sqlite db
    let db = open(dbFile, "", "", "")
    defer: db.close()

    db.exec(sql"""
    Create Table If Not Exists images (
        id      Integer Primary Key AutoIncrement,
        hash    VarChar(32) Not Null,
        format  VarChar(3) Not Null,
        width   Integer,
        height  Integer
    )
    """)
    log.info("Initialized image table")

proc tagTable*() {.raises: [DbError].}=
    log.logScope:
        topics = "setup.tagTable"

    # setup sqlite db
    let db = open(dbFile, "", "", "")
    defer: db.close()

    db.exec(sql"""
    Create Table If Not Exists tags (
        id      Integer Primary Key AutoIncrement,
        tag     VarChar(128) Not Null Unique,
        count   Integer Not Null Default 0
    )
    """)
    log.info("Initialized tag table")

    db.exec(sql"""
    Create Table If Not Exists image_tags (
        image_id    Integer Not Null,
        tag_id      Integer Not Null,
        Foreign Key("image_id") References "images"("id") On Delete Cascade,
        Foreign Key("tag_id") References "tags"("id") On Delete Cascade,
        Unique("image_id", "tag_id")
    )
    """)
    log.info("Initialized image/tag relation table")

proc userTable*() {.raises: [DbError].} =
    log.logScope:
        topics = "setup.userTable"

    let db = open(dbFile, "", "", "")
    defer:
        db.close()

    # create table of users
    db.exec(sql"""
        Create Table If Not Exists users (
            id Integer Primary Key AutoIncrement,
            username Text Not Null Unique,
            password Text Not Null,
            joined_on Integer Default 0, -- Unix time
            logged_in Integer Default 0 -- Unix time
        )
    """)

    log.info("Initialized users table")

proc sessionTable*() {.raises: [DbError].} =
    log.logScope:
        topics = "setup.sessionTable"

    let sessDb = open(sessionDbFile, "", "", "")
    defer:
        sessDb.close()

    sessDb.exec(sql"""
        Create Table If Not Exists sessions (
            sid Text Primary Key Not Null Default "_",
            expires Integer Default 0 -- Unix time, 0 means infinite
        )
    """)
    log.info("Initialized session table")

    # relating users with sessions
    sessDb.exec(sql"""
        Create Table If Not Exists session_user (
            sid Text Not Null,
            user_id Integer Not Null,
            Foreign Key (sid) References sessions(sid) On Delete Cascade
        )
    """)
    log.info("Initialized session/user relation table")

    # relating sessions with one (and ONLY one) anti-CSRF token
    sessDb.exec(sql"""
        Create Table If Not Exists session_acsrf (
            sid Text Not Null,
            token Text,
            Foreign Key (sid) References sessions(sid) On Delete Cascade
        )
    """)
    log.info("Initialized session anti-CSRF table")
