import jester
import ../stb/read as stbr
import ../stb/write as stbw
import ../stb/resize as stbz
import ../settings
import ./exceptions

import std/[md5, tables, strutils]

# db stuff, change for 2.0.0
import std/db_sqlite

{.push raises:[].}

type
    FileUploadRef* = ref object
        contents: string # wanted a ref :(
        length: int
        filename: string
        mime: string

proc newFileUploadRef*(contents: string, length: int, filename, mime: string): FileUploadRef =
    result = FileUploadRef(
        contents: contents,
        length: length,
        filename: filename,
        mime: mime
    )

proc fileFromReq*(
    req: tuple[fields: StringTableRef, body: string]
): FileUploadRef {.raises:[KeyError].} =
    result = newFileUploadRef(
        req.body, req.body.len, req.fields["filename"], req.fields["Content-Type"]
    )

proc clearTags*(imageId: int) {.raises:[DbError].} =
    let db = open(dbFile, "", "", "")
    defer: db.close()
    db.exec(sql"Delete From image_tags Where image_id = ?", imageId)

proc refreshTagCounts*() {.raises:[DbError].} =
    let db = open(dbFile, "", "", "")
    defer: db.close()
    for row in db.instantRows(sql"Select tag_id, Count(1) From image_tags Group By tag_id"):
        db.exec(sql"Update tags Set count = ? Where id = ?", row[1], row[0])

proc assignTags*(imageId: int, tags: string) {.raises:[DbError, BooruException].} =
    let db = open(dbFile, "", "", "")
    defer: db.close()

    # verify image exists
    if db.getValue(sql"Select 1 From images Where id = ?", imageId) == "":
        raise newException(BooruException, "Image " & $imageId & " doesn't exist!")

    for tag in tags.strip.split(" "):
        if tag[0] == '-':
            raise newException(BooruException, "Tag " & tag & " cannot start with a minus!")

        var tagRowId: int64
        try: # does tag exist?
            tagRowId = db.getValue(
                sql"""Select id From tags Where tag = ?""", tag.strip
            ).parseInt()
        except ValueError: # tag doesn't exist, so add it
            tagRowId = db.tryInsertID(sql"""
                Insert Into tags ("tag") Values (?)
            """, tag.strip)
            if tagRowId == -1:
                raise newException(BooruException, "Failed inserting tag " & tag & " into db!")
        # increment count
        # db.exec(
        #     sql"""Update tags Set count = count + 1 Where id = ?""",
        #     tagRowId
        # )

        # add tag to image
        db.exec(sql"""
            Insert Into image_tags (image_id, tag_id) Values (?, ?)
        """, imageId, tagRowId)

    refreshTagCounts()

proc processFile*(file: FileUploadRef, tags: string) {.raises:[
    BooruException, STBIException, IOError
].} =
    let db = open(dbFile, "", "", "")

    let hash = getMD5(file.contents)
    var
        extension: string
        imageId: int64

    try:
        extension = mimeMappings[file.mime]
    except KeyError:
        raise newException(BooruException, "Unsupported file format! Supported formats are jpeg, png.")

    let hashExists = db.getValue(sql"""Select id From images Where hash = ?""", hash)
    if hashExists != "":
        raise newException(BooruException, "An image with this hash already exists: " & hashExists)
    else:
        var
            width = 0
            height = 0

        block saveImageAndThumbnail:
            # copy uploaded file
            writeFile(
                imgDir & "/" & hash & "." & extension,
                file.contents
            )
            # make thumbnail
            var
                channels: int
                imgData, imgThumb: seq[uint8]

            imgData = stbr.loadFromMemory(
                cast[seq[uint8]](file.contents), width, height, channels, stbr.Default
            )

            # calculate thumbsize
            var genThumbSize = [thumbSize, thumbSize]
            if width/height > 1.0: # if wide
                genThumbSize[1] = int(thumbSize.float * (height/width))
            else: # if tall
                genThumbSize[0] = int(thumbSize.float * (width/height))

            imgThumb = stbz.resize(
                imgData, width, height, genThumbSize[0], genThumbSize[1], channels
            )
            stbw.writeJPG(thumbDir & "/" & hash & ".jpg", genThumbSize[0], genThumbSize[1], channels, imgThumb, 30)

        # add new image
        imageId = db.tryInsertID(sql"""
                Insert Into images (hash, format, width, height) Values (?, ?, ?, ?)
        """, hash, file.mime, width, height)

        if imageId == -1:
            raise newException(BooruException, "Failed inserting image into db!")

    db.close()

    imageId.int.assignTags(tags)

proc deleteImage*(imageId: int) {.raises:[DbError].} =
    let db = open(dbFile, "", "", "")
    defer: db.close()
    db.exec(sql"Delete From image_tags Where image_id = ?", $imageId)
    db.exec(sql"Delete From images Where id = ?", $imageId)
