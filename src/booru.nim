import jester

import ./settings
import ./frontend/render as render
import ./backend/setup as setup
import ./backend/upload as upload
import ./backend/exceptions
import ./backend/images as images

import std/[
    strutils, json
]

# exception handling not quite needed here

router mainRouter:
    error Exception:
        resp Http500, render.masterTemplate(
            siteContent=render.exception(exception),
            params=request.params
        )
    error Http404:
        resp Http404, render.masterTemplate(
            siteContent=render.`404`(),
            params=request.params
        )
    get "/":
        setup.folders()
        setup.database()
        redirect "/list"
    get "/list":
        resp render.masterTemplate(
            siteContent=render.siteList(request.params),
            params=request.params
        )
    get "/untagged":
        resp render.masterTemplate(
            siteContent=render.siteUntagged(request.params),
            params=request.params
        )
    get "/taglist":
        resp render.masterTemplate(
            siteContent=render.siteAllTags(request.params),
            params=request.params
        )
    get "/random":
        if request.params.hasKey("q"):
            let paramized = render.getVarsFromParams(request.params)
            let randomImgId = images.getRandomIdFrom(
                images.buildSearchQuery(paramized.query)
            )
            redirect "/entry/" & $randomImgId & "?q=" & paramized.query
        else:
            let randomImgId = images.getRandomIdFrom("Select id From images")
            redirect "/entry/" & $randomImgId
    get "/entry/@id":
        var img: ImageEntryRef
        try:
            img = images.getQueried(
                "Select * From images Where id = ?", $(@"id".parseInt)
            )[0]
        except:
            resp Http404
        resp render.masterTemplate(
            siteContent=render.siteEntry(img,
                query=render.getVarsFromParams(request.params).query
            ),
            params=request.params
        )
    get "/entry/@id/edit":
        var img: ImageEntryRef
        try:
            img = images.getQueried(
                "Select * From images Where id = ?", $(@"id".parseInt)
            )[0]
        except:
            resp Http404
        resp render.masterTemplate(
            siteContent=render.siteEntryEdit(img),
            params=request.params
        )
    post "/entry/@id/edit":
        let
            inImageId = (@"id").parseInt
            newImageTags = request.params.getOrDefault("tags")
        upload.clearTags(inImageId)
        upload.assignTags(inImageId, newImageTags)
        redirect "/entry/" & @"id"
    get "/entry/@id/delete": # loooooooooooooool
        let inImageId = (@"id").parseInt
        upload.deleteImage(inImageId)
        redirect "/list"
    get "/wiki":
        resp render.masterTemplate(
            siteContent=render.siteWiki(),
            params=request.params
        )
    post "/upload":
        # don't upload large files or shit will hit the fan
        if not request.formData.hasKey("tags"):
            raise newException(BooruException, "No tags defined?")
        if not request.formData.hasKey("data"):
            raise newException(BooruException, "No image sent?")

        let rawTags = request.formData["tags"].body

        upload.processFile(
            upload.fileFromReq(request.formData["data"]),
            rawTags
        )
        redirect "/list"
    get "/autocomplete/@word":
        var j = %*{}
        for tagEntry in images.getTagAutocompletes(@"word"):
            j[tagEntry.tag] = %(tagEntry.count)
        resp $j, contentType="application/json"

proc main() =
    let settings = newSettings(bindAddr="127.0.0.1", numThreads=16, staticDir=pubDir)
    var jester = initJester(mainRouter, settings=settings)
    jester.serve()

when isMainModule:
    main()
