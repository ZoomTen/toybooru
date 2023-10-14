import jester

import ./settings
import ./frontend/render as render
import ./backend/setup as setup
import ./backend/upload as upload
import ./backend/exceptions
import ./backend/images as images
import ./backend/authentication as auth
import ./backend/userConfig as config

import std/[
    strutils, json
]

import chronicles as log

# exception handling not quite needed here

template onlyWhenAuthenticated(user: Option[auth.User], body: untyped) =
    if user.isNone():
        resp Http403
    else:
        body

router mainRouter:
    before:
        # throw cookie back at the client
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        auth.invalidateExpiredSessions() # ?

    error Exception:
        resp Http500, render.masterTemplate(
            siteContent=render.exception(exception),
            rq=request
        )

    error Http403:
        resp Http403, render.masterTemplate(
            siteContent=render.`403`(),
            rq=request
        )

    error Http404:
        resp Http404, render.masterTemplate(
            siteContent=render.`404`(),
            rq=request
        )

    get "/":
        resp render.landingPage(request)

    get "/list":
        resp render.masterTemplate(
            siteContent=render.siteList(request),
            rq=request
        )

    get "/untagged":
        resp render.masterTemplate(
            siteContent=render.siteUntagged(request),
            rq=request
        )

    get "/taglist":
        resp render.masterTemplate(
            siteContent=render.siteAllTags(request),
            rq=request
        )

    get "/random":
        let user = auth.getSessionIdFrom(request).getCurrentUser()
        if request.params.hasKey("q"):
            let paramized = render.getVarsFromParams(request.params, user)
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
                rq=request
            ),
            rq=request
        )

    get "/entry/@id/similar":
        var img: ImageEntryRef
        try:
            img = images.getQueried(
                "Select * From images Where id = ?", $(@"id".parseInt)
            )[0]
        except:
            resp Http404
        resp render.masterTemplate(
            siteContent=render.siteSimilar(request, img),
            rq=request
        )

    get "/entry/@id/edit":
        let user = auth.getSessionIdFrom(request).getCurrentUser()

        user.onlyWhenAuthenticated:
            var img: ImageEntryRef
            try:
                img = images.getQueried(
                    "Select * From images Where id = ?", $(@"id".parseInt)
                )[0]
            except:
                resp Http404
            resp render.masterTemplate(
                siteContent=render.siteEntryEdit(img),
                rq=request
            )

    post "/entry/@id/edit":
        let user = auth.getSessionIdFrom(request).getCurrentUser()

        user.onlyWhenAuthenticated:
            let
                inImageId = (@"id").parseInt
                newImageTags = request.params.getOrDefault("tags")
            upload.clearTags(inImageId)
            upload.assignTags(inImageId, newImageTags)
            redirect "/entry/" & @"id"

    get "/entry/@id/delete":
        let user = auth.getSessionIdFrom(request).getCurrentUser()

        user.onlyWhenAuthenticated:
            var img: ImageEntryRef
            try:
                img = images.getQueried(
                    "Select * From images Where id = ?", $(@"id".parseInt)
                )[0]
            except:
                resp Http404
            resp render.masterTemplate(
                siteContent=render.siteEntryConfirmDelete(img),
                rq=request
            )

    post "/entry/@id/delete":
        let user = auth.getSessionIdFrom(request).getCurrentUser()

        user.onlyWhenAuthenticated:
            let inImageId = (@"id").parseInt
            upload.deleteImage(inImageId)
            redirect "/list"

    get "/wiki":
        resp render.masterTemplate(
            siteContent=render.siteWiki(),
            rq=request
        )

    post "/upload":
        let user = auth.getSessionIdFrom(request).getCurrentUser()

        user.onlyWhenAuthenticated:
            # don't upload large files or shit will hit the fan
            if not request.formData.hasKey("tags"):
                raise newException(BooruException, "No tags defined?")
            if not request.formData.hasKey("data"):
                raise newException(BooruException, "No image sent?")

            let
                rawTags = request.formData["tags"].body

            upload.processFile(
                upload.fileFromReq(request.formData["data"]),
                rawTags
            )
            redirect "/list"

    get "/autocomplete/@word":
        var j = %*[]
        for tagEntry in images.getTagAutocompletes(@"word"):
            j.add(%*{"t": tagEntry.tag, "c": tagEntry.count})
        resp $j, contentType="application/json"

    get "/login":
        resp render.masterTemplate(
            siteContent=render.logIn(request),
            rq=request
        )

    post "/login":
        let (user, errors, alreadyLoggedIn, remember) = auth.processLogIn(request)
        if user.isNone():
            resp Http400, render.masterTemplate(
                siteContent=render.logIn(request, errors),
                rq=request
            )
        else:
            if not alreadyLoggedIn:
                auth.doLogIn(
                    auth.getSessionIdFrom(request),
                    user.get(),
                    remember
                )
            redirect "/"

    get "/signup":
        resp render.masterTemplate(
            siteContent=render.signUp(request),
            rq=request
        )

    post "/signup":
        let (user, password, errors) = auth.processSignUp(request)
        if user.isNone():
            resp render.masterTemplate(
                siteContent=render.signUp(request, errors),
                rq=request
            )
        else:
            auth.doSignUp(user.get(), password)
            resp render.masterTemplate(
                siteContent=render.signUpSuccess(),
                rq=request
            )

    get "/logout": # loooooooooooooooool
        auth.getSessionIdFrom(request).logOut()
        redirect "/"

    get "/config":
        let user = auth.getSessionIdFrom(request).getCurrentUser()

        user.onlyWhenAuthenticated:
            resp render.masterTemplate(
                siteContent=render.configPage(rq=request),
                rq=request
            )

    post "/config":
        let user = auth.getSessionIdFrom(request).getCurrentUser()

        user.onlyWhenAuthenticated:
            config.processSetBlacklistConfig(user.get(), request)
            redirect "/config"

proc serverMain() =
    var jester = initJester(
        mainRouter,
        settings=newSettings(
            bindAddr="127.0.0.1", staticDir=pubDir
        )
    )
    jester.serve()

when isMainModule:
    import std/logging
    # Pass all stdlib logging messages to chronicles
    type
        ChroniclesLogger = ref object of Logger

    method log(logger: ChroniclesLogger, level: Level, args: varargs[string, `$`]) =
        log.logScope:
            topics = "stdlib"
        case level:
            of lvlAll: log.info("", message=args.join(" "))
            of lvlDebug: log.debug("", message=args.join(" "))
            of lvlInfo: log.info("", message=args.join(" "))
            of lvlNotice: log.notice("", message=args.join(" "))
            of lvlWarn: log.warn("", message=args.join(" "))
            of lvlError: log.error("", message=args.join(" "))
            of lvlFatal: log.fatal("", message=args.join(" "))
            of lvlNone: discard

    proc newChroniclesLogger(levelThreshold = lvlAll, fmtStr = defaultFmtStr): ChroniclesLogger =
        new result
        result.fmtStr = fmtStr
        result.levelThreshold = levelThreshold

    let chlg = newChroniclesLogger()
    addHandler(chlg)

    # Run server
    setup.folders()
    setup.imageTable()
    setup.tagTable()
    setup.userTable()
    setup.userBlacklistsTable()
    setup.imagePhashesTable()
    setup.sessionTable()
    serverMain()
    auth.invalidateExpiredSessions()
