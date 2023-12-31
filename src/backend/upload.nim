import jester
import stb_image/read as stbr
import stb_image/write as stbw
import ../stb/resize as stbz
import ../settings
import ./validation as validate
import chronicles as log

import std/[tables, strutils, os, osproc, sequtils]

import ../importDb

when NimMajor > 1:
    import checksums/md5
else:
    import std/md5

import ./pHashes as phash

import results
export results

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
): Result[FileUploadRef, string]  =
    try:
        return newFileUploadRef(
            req.body, req.body.len(), req.fields["filename"], req.fields["Content-Type"]
        ).ok()
    except KeyError:
        if not req.fields.hasKey("filename"):
            return err("Missing filename argument")
        if not req.fields.hasKey("Content-Type"):
            return err("Missing content type")
        return err("Something's missing, but I don't know what!")

proc clearTags*(imageId: int): Result[void, string]  =
    withMainDb:
        mainDb.exec(sql"Delete From image_tags Where image_id = ?", imageId)
    return ok()

proc refreshTagCounts*(): Result[void, string]  =
    withMainDb:
        mainDb.exec(sql"""
        Update tags Set count = tag_count.count From (
            Select tag_id, Count(*) As count From image_tags Group By tag_id
        ) as tag_count
        Where tags.id = tag_count.tag_id
        """)
        log.debug("Refresh all tag counts")
    return ok()

proc assignTags*(imageId: int, t: string): Result[void, string]  =
    var tags = ?validate.normalizeSpaces(t.strip())

    if tags == "": return ok()

    # verify image exists
    withMainDb:
        if mainDb.getValue(sql"Select 1 From images Where id = ?", imageId) == "":
            return err("Image " & $imageId & "doesn't exist!")

        var tag = ""

        for rawTag in tags.split(" ").deduplicate():
            if rawTag == "": continue
            if rawTag[0] == '-':
                return err("Tag " & rawTag & "cannot start with a minus!")
            tag = ?sanitizeKeyword(rawTag)

            var tagRowId: int64
            try: # does tag exist?
                tagRowId = mainDb.getValue(
                    sql"""Select id From tags Where tag = ?""", tag.strip()
                ).parseInt()
            except ValueError: # tag doesn't exist, so add it
                tagRowId = mainDb.tryInsertID(sql"""
                    Insert Into tags ("tag") Values (?)
                """, tag.strip())
                if tagRowId == -1:
                    return err("Failed inserting tag " & tag & " into db!")

            # add tag to image
            mainDb.exec(sql"""
                Insert Into image_tags (image_id, tag_id) Values (?, ?)
            """, imageId, tagRowId)

    log.info("Assigned tags to image", imgId=imageId, tags=t)
    return refreshTagCounts()

proc genThumbSize(width, height: int): array[0..1, int] =
    result = [thumbSize, thumbSize]
    if width/height > 1.0: # if wide
        result[1] = int(thumbSize.float() * (height/width))
    else: # if tall
        result[0] = int(thumbSize.float() * (width/height))

proc processFile*(file: FileUploadRef, tags: string): Result[void, string] =
    # TODO: transactionize this; image analysis is done first, try insert to table and only after it's successful, will the files be uploaded (?)
    
    let mimeMappings = makeMimeMappings()

    let hash = getMD5(file.contents)
    var
        extension: string
        imageId: int64

    try:
        extension = mimeMappings[file.mime]
    except KeyError:
        return err("Unsupported file format! Supported formats are jpeg, png, mp4.")

    withMainDb:
        let hashExists = mainDb.getValue(sql"Select id From images Where hash = ?", hash)
        if hashExists != "":
            return err("An image with this hash already exists: " & hashExists)

    var
        width = 0
        height = 0

    block saveImageAndThumbnail:
        let
            exportName = imgDir & "/" & hash & "." & extension
            thumbName = thumbDir & "/" & hash & ".jpg"

        # copy uploaded file
        try:
            writeFile(exportName, file.contents)
        except IOError as e:
            return err("Can't copy file, " & e.msg)

        try:
            exportName.inclFilePermissions({fpGroupRead, fpOthersRead})
        except OSError as e:
            return err("Setting perms for copied file failed, " & e.msg)

        # make thumbnail
        if extension in ["mp4"]:
            try:
                let
                    ffprobe = findExe("ffprobe")
                    ffmpeg = findExe("ffmpeg")

                if ffprobe == "" or ffmpeg == "":
                    return err("This server doesn't support video files :(")

                # https://stackoverflow.com/a/29585066
                var (wh, ex) = execCmdEx(
                    ffprobe & " -v quiet -select_streams v -show_entries stream=width,height -of csv=p=0:s=x " & exportName
                )
                if ex != 0:
                    return err("Error processing video")
                let
                    whx = wh.split("x")
                    width = whx[0].strip().parseInt()
                    height = whx[1].strip().parseInt()
                    genThumbSize = genThumbSize(width, height)

                (wh, ex) = execCmdEx(
                    ffmpeg & " -i " & exportName & " -ss 0 -vframes 1 -s " &
                    $genThumbSize[0] & "x" & $genThumbSize[1] & " -y " & thumbName
                )
            except OSError as e:
                return err(e.msg)
            except IOError as e:
                return err(e.msg)
            except ValueError as e:
                return err(e.msg)

        else:
            var
                channels: int
                imgData, imgThumb: seq[uint8]

            try:
                imgData = stbr.loadFromMemory(
                    cast[seq[uint8]](file.contents), width, height, channels, stbr.Default
                )

                # calculate thumbsize
                let genThumbSize = genThumbSize(width, height)

                imgThumb = stbz.resize(
                    imgData, width, height, genThumbSize[0], genThumbSize[1], channels
                )

                stbw.writeJPG(
                    thumbName,
                    genThumbSize[0], genThumbSize[1],
                    channels, imgThumb,
                    30
                )
            except STBIException as e:
                return err(e.msg)

        try:
            thumbName.inclFilePermissions({fpGroupRead, fpOthersRead})
        except OSError as e:
            return err(e.msg)

        # add new image
        withMainDb:
            imageId = mainDb.tryInsertID(sql"""
                    Insert Into images (hash, format, width, height) Values (?, ?, ?, ?)
            """, hash, file.mime, width, height)

            if imageId == -1:
                return err("Failed inserting image into db!")

            if not (extension in ["mp4"]):
                let pHash = ?phash.pHash(file.contents)
                mainDb.exec(sql"Insert Into image_phashes(image_id, phash) Values (?, ?)", imageId, pHash)
                log.info("Assigned hash to new image", imgId=imageId, hash=pHash)

    log.info("Added new image", imgId=imageId)
    return imageId.int.assignTags(tags)

proc deleteImage*(imageId: int): Result[void, string]  =
    let mimeMappings = makeMimeMappings()

    withMainDb:
        let row = mainDb.getRow(sql"Select hash, format From images Where id = ?", $imageId)
        if row != @[]:
            # delete the file first
            try:
                let
                    hash = row[0]
                    extension = mimeMappings[row[1]]

                removeFile(imgDir & "/" & hash & "." & extension) # exportName
                removeFile(thumbDir & "/" & hash & ".jpg") # thumbName
            except OSError as e:
                return err(e.msg)
            except KeyError as e:
                return err(e.msg)

            # then delete it from the db
            mainDb.exec(sql"Delete From image_tags Where image_id = ?", $imageId)
            mainDb.exec(sql"Delete From image_phashes Where image_id = ?", $imageId)
            mainDb.exec(sql"Delete From images Where id = ?", $imageId)
            log.info("Image deleted", imgId=imageId)
        else:
            return err("Invalid image")

    return ok()
