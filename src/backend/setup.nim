import std/os
import ../settings

when defined(usePostgres):
    when NimMajor > 1:
        import db_connector/db_postgres
    else:
        import std/db_postgres
else:
    when NimMajor > 1:
        import db_connector/db_sqlite
    else:
        import std/db_sqlite

import chronicles as log

proc folders*() =
    log.logScope:
        topics = "setup.folders"

    # setup image bins
    for dir in [imgDir, thumbDir]:
        log.info("Created image folder", dir=dir)
        createDir(dir)

proc imageTable*() =
    log.logScope:
        topics = "setup.imageTable"

    # setup sqlite db
    let db = open(mainDbUrl, mainDbUser, mainDbPass, mainDbDatabase)
    defer: db.close()

    when defined(usePostgres):
        db.exec(sql"""
        Create Table If Not Exists images (
            id      Serial Primary Key,
            hash    VarChar(32) Not Null,
            format  VarChar(3) Not Null,
            width   Integer,
            height  Integer
        )
        """)
    else:
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

proc tagTable*() =
    log.logScope:
        topics = "setup.tagTable"

    # setup sqlite db
    let db = open(mainDbUrl, mainDbUser, mainDbPass, mainDbDatabase)
    defer: db.close()

    when defined(usePostgres):
        db.exec(sql"""
        Create Table If Not Exists tags (
            id      Serial Primary Key,
            tag     VarChar(128) Not Null Unique,
            count   Integer Not Null Default 0
        )
        """)
    else:
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
        Unique(image_id, tag_id)
    )
    """)
    log.info("Initialized image/tag relation table")

proc userTable*()  =
    log.logScope:
        topics = "setup.userTable"

    let db = open(mainDbUrl, mainDbUser, mainDbPass, mainDbDatabase)
    defer:
        db.close()

    # create table of users
    when defined(usePostgres):
        db.exec(sql"""
            Create Table If Not Exists users (
                id Serial Primary Key,
                username Text Not Null Unique,
                password Text Not Null,
                joined_on Integer Default 0, -- Unix time
                logged_in Integer Default 0 -- Unix time
            )
        """)
    else:
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

proc userBlacklistsTable*()  =
    log.logScope:
        topics = "setup.userBlacklistsTable"

    let db = open(mainDbUrl, mainDbUser, mainDbPass, mainDbDatabase)
    defer: db.close()

    db.exec(sql"""
        Create Table If Not Exists user_blacklists (
            user_id Integer Not Null Unique,
            blacklist Text Not Null Default ?,
            Foreign Key (user_id) References users(id) On Delete Cascade
        )
    """, defaultBlacklist)
    log.info("Initialized user blacklists table")

proc imagePhashesTable*()  =
    log.logScope:
        topics = "setup.imagePhashesTable"

    let db = open(mainDbUrl, mainDbUser, mainDbPass, mainDbDatabase)
    defer: db.close()

    db.exec(sql"""
        Create Table If Not Exists image_phashes (
            image_id Integer Not Null Unique,
            phash Integer Not Null,
            Foreign Key (image_id) References images(id) On Delete Cascade
        )
    """)
    log.info("Initialized image perceptual hashes table")

proc sessionTable*()  =
    log.logScope:
        topics = "setup.sessionTable"

    let sessDb = open(sessionDbUrl, sessionDbUser, sessionDbPass, sessionDbDatabase)
    defer:
        sessDb.close()

    sessDb.exec(sql"""
        Create Table If Not Exists sessions (
            sid Text Primary Key Not Null Default '',
            expires Integer Default 0 -- Unix time, 0 means infinite
        )
    """)
    log.info("Initialized session table")

    # relating users with sessions
    sessDb.exec(sql"""
        Create Table If Not Exists sessions_users (
            sid Text Not Null,
            user_id Integer Not Null,
            Foreign Key (sid) References sessions(sid) On Delete Cascade,
            Unique(sid, user_id)
        )
    """)
    log.info("Initialized session/user relation table")

    # relating sessions with one (and ONLY one) anti-CSRF token
    sessDb.exec(sql"""
        Create Table If Not Exists session_acsrf (
            sid Text Not Null,
            token Text,
            Foreign Key (sid) References sessions(sid) On Delete Cascade,
            Unique(sid, token)
        )
    """)
    log.info("Initialized session anti-CSRF table")
