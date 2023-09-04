import std/os
import ../settings

# db stuff, change for 2.0.0
import std/db_sqlite

{.push raises:[].}

proc folders*() {.raises: [OSError, IOError].}=
    # setup image bins
    for dir in [imgDir, thumbDir]:
        createDir(dir)

proc database*() {.raises: [DbError].}=
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
    db.exec(sql"""
    Create Table If Not Exists tags (
        id      Integer Primary Key AutoIncrement,
        tag     VarChar(128) Not Null Unique,
        count   Integer Not Null Default 0
    )
    """)
    db.exec(sql"""
    Create Table If Not Exists image_tags (
        image_id    Integer Not Null,
        tag_id      Integer Not Null,
        Foreign Key("image_id") References "images"("id") On Delete Cascade,
        Foreign Key("tag_id") References "tags"("id") On Delete Cascade,
        Unique("image_id", "tag_id")
    )
    """)
