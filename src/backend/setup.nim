import std/os
import ../settings
import ../importDb

import chronicles as log

{.push raises:[].}

proc folders*() {.raises:[IOError, OSError].} =
    log.info("Created image folder")
    createDir(imgDir)

    log.info("Created thumbnail folder")
    createDir(thumbDir)

proc imageTable*(): Result[void, string] =
    withMainDb:
        when defined(usePostgres):
            mainDb.exec(sql"""
            Create Table If Not Exists images (
                id      Integer Primary Key Generated Always As Identity,
                hash    VarChar(32) Not Null,
                format  VarChar(32) Not Null,
                width   Integer,
                height  Integer
            )
            """)
        else:
            mainDb.exec(sql"""
            Create Table If Not Exists images (
                id      Integer Primary Key AutoIncrement,
                hash    VarChar(32) Not Null,
                format  VarChar(32) Not Null,
                width   Integer,
                height  Integer
            )
            """)
        log.info("Initialized image table")
    return ok()

proc tagTable*(): Result[void, string] =
    withMainDb:
        when defined(usePostgres):
            mainDb.exec(sql"""
            Create Table If Not Exists tags (
                id      Integer Primary Key Generated Always As Identity,
                tag     VarChar(128) Not Null Unique,
                count   Integer Not Null Default 0
            )
            """)
        else:
            mainDb.exec(sql"""
            Create Table If Not Exists tags (
                id      Integer Primary Key AutoIncrement,
                tag     VarChar(128) Not Null Unique,
                count   Integer Not Null Default 0
            )
            """)
        log.info("Initialized tag table")

        mainDb.exec(sql"""
        Create Table If Not Exists image_tags (
            image_id    Integer Not Null,
            tag_id      Integer Not Null,
            Foreign Key("image_id") References "images"("id") On Delete Cascade,
            Foreign Key("tag_id") References "tags"("id") On Delete Cascade,
            Unique(image_id, tag_id)
        )
        """)
        log.info("Initialized image/tag relation table")
    return ok()

proc userTable*(): Result[void, string]  =
    # create table of users
    withMainDb:
        when defined(usePostgres):
            mainDb.exec(sql"""
                Create Table If Not Exists users (
                    id Integer Primary Key Generated Always As Identity,
                    username Text Not Null Unique,
                    password Text Not Null,
                    joined_on Integer Default 0, -- Unix time
                    logged_in Integer Default 0 -- Unix time
                )
            """)
        else:
            mainDb.exec(sql"""
                Create Table If Not Exists users (
                    id Integer Primary Key AutoIncrement,
                    username Text Not Null Unique,
                    password Text Not Null,
                    joined_on Integer Default 0, -- Unix time
                    logged_in Integer Default 0 -- Unix time
                )
            """)

        log.info("Initialized users table")
    return ok()

proc userBlacklistsTable*(): Result[void, string]  =
    withMainDb:
        mainDb.exec(sql"""
            Create Table If Not Exists user_blacklists (
                user_id Integer Not Null Unique,
                blacklist Text Not Null Default ?,
                Foreign Key (user_id) References users(id) On Delete Cascade
            )
        """, defaultBlacklist)
        log.info("Initialized user blacklists table")
    return ok()

proc imagePhashesTable*(): Result[void, string]  =
    withMainDb:
        mainDb.exec(sql"""
            Create Table If Not Exists image_phashes (
                image_id Integer Not Null Unique,
                phash BigInt Not Null,
                Foreign Key (image_id) References images(id) On Delete Cascade
            )
        """)
        log.info("Initialized image perceptual hashes table")
    return ok()

proc sessionTable*(): Result[void, string]  =
    withSessionDb:
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
    return ok()