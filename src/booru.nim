import jester

import ./settings
import ./frontend/render as render
import ./backend/setup as setup
import ./backend/upload as upload
import ./backend/exceptions
import ./backend/images as images
import ./backend/authentication as auth

import std/[
    strutils, json
]

import chronicles as log

# exception handling not quite needed here

router mainRouter:
    error Exception:
        setCookie(sessionCookieName, auth.getSessionIdFrom(request)) # throw cookie back at the client
        resp Http500, render.masterTemplate(
            siteContent=render.exception(exception),
            rq=request
        )

    error Http404:
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        resp Http404, render.masterTemplate(
            siteContent=render.`404`(),
            rq=request
        )

    get "/":
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        resp render.landingPage(request)

    get "/list":
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        resp render.masterTemplate(
            siteContent=render.siteList(request),
            rq=request
        )

    get "/untagged":
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        resp render.masterTemplate(
            siteContent=render.siteUntagged(request.params),
            rq=request
        )

    get "/taglist":
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        resp render.masterTemplate(
            siteContent=render.siteAllTags(request.params),
            rq=request
        )

    get "/random":
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
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
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
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
            rq=request
        )

    get "/entry/@id/edit":
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
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
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        let
            inImageId = (@"id").parseInt
            newImageTags = request.params.getOrDefault("tags")
        upload.clearTags(inImageId)
        upload.assignTags(inImageId, newImageTags)
        redirect "/entry/" & @"id"

    get "/entry/@id/delete": # loooooooooooooool
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        let inImageId = (@"id").parseInt
        upload.deleteImage(inImageId)
        redirect "/list"

    get "/wiki":
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        resp render.masterTemplate(
            siteContent=render.siteWiki(),
            rq=request
        )

    post "/upload":
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
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
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        var j = %*{}
        for tagEntry in images.getTagAutocompletes(@"word"):
            j[tagEntry.tag] = %(tagEntry.count)
        resp $j, contentType="application/json"

    get "/login":
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        resp render.masterTemplate(
            siteContent=render.logIn(request),
            rq=request
        )

    post "/login":
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        let (user, errors, alreadyLoggedIn) = auth.processLogIn(request)
        if user.isNone():
            resp Http400, render.masterTemplate(
                siteContent=render.logIn(request, errors),
                rq=request
            )
        else:
            if not alreadyLoggedIn:
                auth.doLogIn(
                    auth.getSessionIdFrom(request),
                    user.get()
                )
            redirect "/"

    get "/signup":
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        resp render.masterTemplate(
            siteContent=render.signUp(request),
            rq=request
        )

    post "/signup":
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
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
        setCookie(sessionCookieName, auth.getSessionIdFrom(request))
        auth.getSessionIdFrom(request).logOut()
        redirect "/"


proc serverMain() =
    let settings = newSettings(bindAddr="127.0.0.1", numThreads=16, staticDir=pubDir)
    var jester = initJester(mainRouter, settings=settings)
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
    setup.sessionTable()
    auth.invalidateExpiredSessions()
    serverMain()
