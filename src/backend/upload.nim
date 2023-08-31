import jester
import stb_image/read as stbr
import stb_image/write as stbw
import ../stb/resize as stbz
import ../settings
import ./exceptions

import std/[md5, tables, strutils, os, osproc]

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
    if tags.strip == "": return

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

proc genThumbSize(width, height: int): array[0..1, int] =
    result = [thumbSize, thumbSize]
    if width/height > 1.0: # if wide
        result[1] = int(thumbSize.float * (height/width))
    else: # if tall
        result[0] = int(thumbSize.float * (width/height))

proc processFile*(file: FileUploadRef, tags: string) {.raises:[
    BooruException, STBIException, IOError, OSError, Exception
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
            let
                exportName = imgDir & "/" & hash & "." & extension
                thumbName = thumbDir & "/" & hash & ".jpg"
            # copy uploaded file
            writeFile(
                exportName,
                file.contents
            )
            # make thumbnail
            if extension in ["mp4"]:
                let
                    ffprobe = findExe("ffprobe")
                    ffmpeg = findExe("ffmpeg")
                if ffprobe == "" or ffmpeg == "":
                    raise newException(BooruException, "This server doesn't support video files :(")
                # https://stackoverflow.com/a/29585066
                var (wh, ex) = execCmdEx(
                    ffprobe & " -v quiet -select_streams v -show_entries stream=width,height -of csv=p=0:s=x " & exportName
                )
                if ex != 0:
                    raise newException(BooruException, "Error processing video!")
                let
                    whx = wh.split("x")
                    width = whx[0].strip.parseInt
                    height = whx[1].strip.parseInt
                    genThumbSize = genThumbSize(width, height)

                (wh, ex) = execCmdEx(
                    ffmpeg & " -i " & exportName & " -ss 0 -vframes 1 -s " &
                    $genThumbSize[0] & "x" & $genThumbSize[1] & " -y " & thumbName
                )

            else:
                var
                    channels: int
                    imgData, imgThumb: seq[uint8]

                imgData = stbr.loadFromMemory(
                    cast[seq[uint8]](file.contents), width, height, channels, stbr.Default
                )

                # calculate thumbsize
                let genThumbSize = genThumbSize(width, height)

                imgThumb = stbz.resize(
                    imgData, width, height, genThumbSize[0], genThumbSize[1], channels
                )
                stbw.writeJPG(thumbName, genThumbSize[0], genThumbSize[1], channels, imgThumb, 30)

        # add new image
        imageId = db.tryInsertID(sql"""
                Insert Into images (hash, format, width, height) Values (?, ?, ?, ?)
        """, hash, file.mime, width, height)

        if imageId == -1:
            raise newException(BooruException, "Failed inserting image into db!")

    db.close()

    imageId.int.assignTags(tags)

proc deleteImage*(imageId: int) {.raises:[DbError, BooruException, OSError, KeyError].} =
    let db = open(dbFile, "", "", "")
    defer: db.close()
    let row = db.getRow(sql"Select hash, format From images Where id = ?", $imageId)
    if row != @[]:
        # delete the file first
        let
            hash = row[0]
            extension = mimeMappings[row[1]]
        removeFile(imgDir & "/" & hash & "." & extension) # exportName
        removeFile(thumbDir & "/" & hash & ".jpg") # thumbName
        # then delete it from the db
        db.exec(sql"Delete From image_tags Where image_id = ?", $imageId)
        db.exec(sql"Delete From images Where id = ?", $imageId)
    else:
        raise newException(BooruException, "Invalid image")
