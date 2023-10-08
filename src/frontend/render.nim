import jester
import karax/[
    karaxdsl, vdom
]
import std/[
    strutils, math, sequtils, algorithm
]
import ../backend/images as images
import ../backend/validation as validate
import ../backend/authentication as auth
import ../backend/userConfig as config
import ../settings

when NimMajor > 1:
    import db_connector/db_sqlite
else:
    import std/db_sqlite

import chronicles as log

{.push raises: [].}

type
    PageVars* = tuple
        query: string ## contains raw query!
        originalQuery: string
        pageNum: int
        numResults: int

proc getVarsFromParams*(params: Table, user: Option[auth.User]): PageVars =
    log.logScope:
        topics = "getVarsFromParams"

    let blacklistDef = if user.isNone():
        try:
            log.debug("Default blacklist set",
                    blacklist=defaultBlacklist
            )
            validate.sanitizeBlacklist(defaultBlacklist)
        except ValueError:
            ""
    else:
        try:
            let blist = config.getBlacklistConfig(user.get())
            log.debug("Custom blacklist set",
                    blacklist=blist
            )
            validate.sanitizeBlacklist(blist)
        except DbError:
            ""
        except ValueError:
            ""

    log.debug("Converted blacklist to query to be appended", blacklistDef=blacklistDef)

    result.query = params.getOrDefault("q", "")

    result.originalQuery = result.query

    result.query = result.query & " " & blacklistDef

    result.pageNum = try:
            params.getOrDefault("page", "0").parseInt()
        except ValueError: 0
    result.numResults = try:
            params.getOrDefault("count", $defaultNumResults).parseInt()
        except ValueError: defaultNumResults

proc genericMakeTagText(tagGet: TagTuple): VNode {.raises: [ValueError].} =
    let isNamespaced = tagGet.tag.find(":")
    if isNamespaced == -1:
        return buildHtml(span):
            a(href="/list?q=$#" % tagGet.tag): text tagGet.tag
            text " (" & $tagGet.count & ")"
    else:
        let nsName = tagGet.tag.substr(0, isNamespaced-1)
        return buildHtml(span):
            a(href="/list?q=$#" % tagGet.tag, class="namespacedTag namespace-$#" % nsName): text tagGet.tag
            text " (" & $tagGet.count & ")"

proc compareTags(a, b: TagTuple): int =
    cmp(a.tag, b.tag)

proc toTagDisplay(tagEntry: TagTuple, query: string = ""): VNode {.raises: [ValueError].} =
    let q = query.strip()
    return buildHtml(li):
        a(href="/list?q="&q&"+"&tagEntry.tag, title="add to search"): text "+"
        text " "
        a(href="/list?q="&q&"+-"&tagEntry.tag, title="exclude from search"): text "-"
        text " "
        a(href="/wiki/$#" % tagEntry.tag, title="boot up wiki page"): text "?"
        text " "
        genericMakeTagText tagEntry

proc getPopularTagsSidebar(): VNode {.raises: [DbError, ValueError].}=
    var popularTags = images.getMostPopularTagsGeneral(25)
    popularTags.sort(compareTags)
    return buildHtml(nav):
        h2: text "Popular tags"
        ul(id="navTags", class="navLinks"):
            for tagEntry in popularTags:
                tagEntry.toTagDisplay
        # a(href="#"): text "View all tags"

proc getImageTagsSidebar*(img: ImageEntryRef, query: string=""): VNode {.raises: [DbError, ValueError].}=
    let tags = images.getTagsFor(img)
    return buildHtml(nav):
        if tags.len > 0:
            h2: text "Tags in image"
            ul(id="navTags", class="navLinks"):
                for tagEntry in tags:
                    tagEntry.toTagDisplay(query)
        a(href="/taglist"): text "View all tags"

proc getImageTagsOfListSidebar*(rq: Request): VNode {.raises: [DbError, ValueError, IOSelectorsException, Exception].} =
    log.logScope:
        topics = "getImageTagsOfListSidebar"

    let params = rq.params

    log.debug("Get image tags to sidebar")

    let
        paramTuple = params.getVarsFromParams(auth.getSessionIdFrom(rq).getCurrentUser())
        pageNum = paramTuple.pageNum
        numResults = paramTuple.numResults
    var
        query = ""
        userQuery = ""
        imageList: seq[ImageEntryRef] = @[]
    try:
        if paramTuple.query.strip() != "":
            query = validate.sanitizeQuery(paramTuple.query)
        if paramTuple.originalQuery.strip() != "":
            userQuery = validate.sanitizeQuery(paramTuple.originalQuery)
        let
            imgSqlQuery = images.buildSearchQuery(query)
            numPages = ceilDiv(
                images.getCountOfQuery(imgSqlQuery),
                numResults
            )
        imageList = images.getQueried(
            images.buildPageQuery(
                imgSqlQuery,
                pageNum=pageNum, numResults=numResults,
                descending=true
            )
        )
    except ValueError as e:
        log.debug("Invalid query", query=paramTuple.query)

    var totalTags: seq[TagTuple] = @[]

    for img in imageList:
        totalTags &= images.getTagsFor(img)

    totalTags = totalTags.deduplicate()
    totalTags.sort(compareTags)

    return buildHtml(nav(class="headerBox")):
        h2: text "Tags for images in list"
        ul(id="navTags", class="navLinks"):
            for tagEntry in totalTags:
                tagEntry.toTagDisplay(userQuery)
        a(href="/taglist"): text "View all tags"

proc relatedContent(query: string = ""): VNode =
    return buildHtml(aside):
        h2: text "Related"
        ul(class="navLinks", id="galleryLinks"):
            if query.strip == "":
                li: a(href="/random"): text "Random pic"
            else:
                li: a(href="/random?q="&query): text "Random pic from this query"
            li: a(href="/untagged"): text "View untagged posts"

proc siteHeader(rq: Request): VNode {.raises:[IOSelectorsException, Exception].} =
    let user = auth.getSessionIdFrom(rq).getCurrentUser()
    let (query, originalQuery, pageNum, numResults) = rq.params.getVarsFromParams(user)
    return buildHtml(header):
        nav(id="mainMenu"):
            tdiv(id="titleAndSearch"):
                h1: text siteName
                form(class="inputAndSubmit", action="/list", `method`="get"):
                    input(type="search", name="q", autocomplete="off", placeholder="find some_tags", id="searchInput", value=originalQuery)
                    input(type="submit", value="Find")
                hr: text ""
                ul(class="hidden"):
                    li:
                        a(href="#"): text "Skip navigation"
                    li:
                        a(href="#"): text "Skip to tags"
            hr: text ""
            ul(class="navLinks", id="headerLinks"):
                if user.isNone():
                    li:
                        a(href="/login"): text "Log in"
                else:
                    li:
                        text "Hey, "
                        a(href="/config"): bold: text user.get().name
                    li:
                        a(href="/logout"): text "Log out"
                li:
                    a(href="/"): text "Home"
                li:
                    a(href="/list"): text "Listing"
                li:
                    a(href="/wiki"): text "Wiki"

proc uploadForm(): VNode =
    return buildHtml(
        form(class="formBox",
             action="/upload",
             `method`="post",
             enctype="multipart/form-data")
        ):
            h2:
                text "Upload"
            input(name="data", type="file")
            tdiv(class="textAreaAndSubmit"):
                textarea(name="tags",
                         placeholder="tag_me and_stuff yo",
                         id="submitTagBox"
                )
                input(type="submit")

proc buildGalleryPagination(numPages, pageNum, numResults: int, query: string): VNode =
    let appendParam = if numResults != defaultNumResults:
            "&count=" & $numResults
        else:
            ""
    
    let queryParam = if query.strip() != "":
            "&q=" & query
        else:
            ""

    return buildHtml(nav(id="pageNav")):
        h2(class="hidden"): text "Pages"
        ul(class="navLinks"):
            # prev/first
            if pageNum == 0:
                li(aria-label="First"): text "<<"
                li(aria-label="Prev"): text "<"
            else:
                li: a(aria-label="First", href="?page=0" & appendParam & queryParam): text "<<"
                li: a(aria-label="Prev", href="?page=" & $(pageNum-1) & appendParam & queryParam): text "<"

            # page numbers, show 2 pages around current page
            for i in 0..<numPages:
                if i in pageNum-2..pageNum+2:
                    if i == pageNum:
                        li: text $(i+1)
                    else:
                        li: a(href="?page=" & $i & appendParam & queryParam): text $(i+1)

            # next/last
            if pageNum == numPages-1:
                li(aria-label="Next"): text ">"
                li(aria-label="Last"): text ">>"
            else:
                li: a(aria-label="Next", href="?page=" & $(pageNum+1) & appendParam & queryParam): text ">"
                li: a(aria-label="Last", href="?page=" & $(numPages-1) & appendParam & queryParam): text ">>"

proc buildGallery(imageList: seq[ImageEntryRef], query: string): VNode {.raises: [DbError, ValueError].} =
    let queryAddition = if query.strip() != "":
                "?q=" & query
            else: ""
    return buildHtml(ul(class="galleryItems navLinks")):
        for img in imageList:
            li:
                a(href="/entry/" & $img.id & queryAddition): img(
                        src="/thumbs/" & img.hash & ".jpg",
                        title=images.tagsAsString(
                            images.getTagsFor(img)
                        )
                    )

proc siteList*(rq: Request): VNode  {.raises: [DbError, ValueError, IOSelectorsException, Exception].} =
    log.logScope:
        topics = "siteList"

    log.debug("Get images to gallery display")

    let
        user = auth.getCurrentUser(auth.getSessionIdFrom(rq))
        params = rq.params
        paramTuple = params.getVarsFromParams(user)
        pageNum = paramTuple.pageNum
        numResults = paramTuple.numResults
    var
        query = ""
        userQuery = ""
        imageList: seq[ImageEntryRef] = @[]
        numPages = 0
    try:
        if paramTuple.query.strip() != "":
            query = validate.sanitizeQuery(paramTuple.query)
        if paramTuple.originalQuery.strip() != "":
            userQuery = validate.sanitizeQuery(paramTuple.originalQuery)
        let imgSqlQuery = images.buildSearchQuery(query)
        numPages = ceilDiv(
            images.getCountOfQuery(imgSqlQuery),
            numResults
        )
        imageList = images.getQueried(
            images.buildPageQuery(
                imgSqlQuery,
                pageNum=pageNum, numResults=numResults,
                descending=true
            )
        )
    except ValueError as e:
        log.debug("Invalid query", query=paramTuple.query)

    return buildHtml(main):
        tdiv(class="contentWithTags"):
            section(id="gallery"):
                h2: text "Posts"
                if imageList.len < 1:
                    span: text "Nothing here!"
                else:
                    imageList.buildGallery(userQuery)
                    numPages.buildGalleryPagination(pageNum, numResults, userQuery)
            section(id="tags"):
                if user.isSome():
                    uploadForm()
                if imageList.len >= 1:
                    getImageTagsOfListSidebar(rq)
                    relatedContent(userQuery)

proc siteUntagged*(rq: Request): VNode {.raises: [DbError, ValueError, IOSelectorsException, Exception].} =
    let
        params = rq.params
        paramTuple = params.getVarsFromParams(auth.getSessionIdFrom(rq).getCurrentUser())
        query = ""
        pageNum = paramTuple.pageNum
        numResults = paramTuple.numResults
        imgSqlQuery = "Select * From images Where id Not In (Select image_id From image_tags)"
        numPages = ceilDiv(
            images.getCountOfQuery(imgSqlQuery),
            numResults
        )
        imageList = images.getQueried(
            images.buildPageQuery(
                imgSqlQuery,
                pageNum=pageNum, numResults=numResults,
                descending=true
            )
        )

    return buildHtml(main):
        tdiv(class="contentWithTags"):
            section(id="gallery"):
                h2: text "Untagged Posts"
                if imageList.len < 1:
                    span: text "No untagged posts :)"
                else:
                    imageList.buildGallery(query)
                    numPages.buildGalleryPagination(pageNum, numResults, query)

proc siteEntry*(img: ImageEntryRef, rq: Request): VNode {.raises: [DbError, KeyError, ValueError, IOSelectorsException, Exception].} =
    let mimeMappings = makeMimeMappings()
    let
        user = auth.getSessionIdFrom(rq).getCurrentUser()
        paramTuple = rq.params.getVarsFromParams(user)
        ext = mimeMappings[img.formatMime]
        imgLink = "/images/" & img.hash & "." & ext
    return buildHtml(main):
        tdiv(class="contentWithTags"):
            section(id="image"):
                if ext in ["mp4"]:
                    video(controls="1"):
                        source(src=imgLink, type=img.formatMime)
                        a(href=imgLink): text "View video"
                else:
                    img(
                        src=imgLink,
                        title=images.tagsAsString(
                            images.getTagsFor(img)
                        )
                    )
                dl(id="imageInfo"):
                    # tdiv:
                    #     dt: text "Uploader"
                    #     dd: text "WhatTheFuckWhA"
                    # tdiv:
                    #     dt: text "Source"
                    #     dd:
                    #         a(href="#"): text "nowhere"
                    if user.isSome():
                        tdiv:
                            dt: text "Actions"
                            dd:
                                ul:
                                    li: a(href="/entry/$#/edit" % $img.id): text "Edit"
                                    li: a(href="/entry/$#/delete" % $img.id): text "Delete"
            section(id="tags"):
                getImageTagsSidebar(img, paramTuple.originalQuery)
                relatedContent(paramTuple.originalQuery)

proc siteEntryEdit*(img: ImageEntryRef): VNode  {.raises: [DbError, ValueError].} =
    let mimeMappings = makeMimeMappings()
    return buildHtml(main):
        section(id="image"):
            img(
                src="/images/" & img.hash & "." & mimeMappings[img.formatMime],
                width="500"
            )
            dl(id="imageInfo"):
                form(class="headerBox", `method`="post"):
                    tdiv(class="textAreaAndSubmit"):
                        textarea(
                            name="tags",
                            placeholder="insert_tags_here",
                            id="editTagBox"
                        ): text images.tagsAsString(images.getTagsFor(img))
                        input(type="submit", value="Post")

proc siteWiki*(): VNode =
    return buildHtml(main):
        section(id="wiki"):
            h2: text "Wiki"
            # TODO: markdown and RST conversion here
            p: text "Not available yet!"

proc siteAllTags*(rq: Request): VNode {.raises: [DbError, ValueError, Exception].} =
    let (query, originalQuery, pageNum, numResults) = rq.params.getVarsFromParams(
        auth.getSessionIdFrom(rq).getCurrentUser()
    )
    let tags = images.getAllTags()
    return buildHtml(main):
        section(id="wiki"):
            h2: text "All tags"
            ul(id="allTags", class="navLinks"):
                for tagEntry in tags:
                    tagEntry.toTagDisplay(query)

proc masterTemplate*(title: string = "", rq: Request, siteContent: VNode): string {.raises:[IOSelectorsException, Exception, ValueError, KeyError].}=
    let
        vn = buildHtml(html):
            head:
                meta(charset="utf-8")
                title: text(if title.strip == "":
                        siteName
                    else:
                        title & " - " & siteName
                )
                meta(name="viewport", content="width=device-width,initial-scale=1")
                link(rel="stylesheet", href="/assets/screen.css")
            body:
                tdiv(id="pageContainer"):
                    siteHeader(rq)
                    siteContent
                footer:
                    hr: text ""
                    text "© 2023 Zumi. Source code is available "
                    a(href=sourceLink): text "here"
                    text "."
                    br: discard
                    text "ver. " & siteRevHash & " (" & siteRevDate & ")"
                script(src="/assets/autocomplete.js")
    return "<!DOCTYPE html>\n" & $vn

proc landingPage*(rq: Request): string {.raises: [ValueError, DbError, IOSelectorsException, Exception].}=
    let
        postCount = images.getCountOfQuery("Select * From images")
        vn = buildHtml(html):
            head:
                meta(charset="utf-8")
                title: text siteName
                meta(name="viewport", content="width=device-width,initial-scale=1")
                link(rel="stylesheet", href="/assets/screen.css")
            body:
                tdiv(id="landingContainer"):
                    tdiv:
                        siteHeader(rq)
                        main:
                            p(class="landingStats"): text "Browse through $# images" % [($postCount).insertSep(',')]
                footer:
                    hr: text ""
                    text "© 2023 Zumi. Source code is available "
                    a(href=sourceLink): text "here"
                    text "."
                    br: discard
                    text "ver. " & siteRevHash & " (" & siteRevDate & ")"
                script(src="/assets/autocomplete.js")
    return "<!DOCTYPE html>\n" & $vn

proc exception*(exception: ref Exception): VNode =
    log.logScope:
        topics = "exception"

    log.error("Exception occured!", name=exception.name, message=exception.msg)

    return buildHtml(main):
        section(id="wiki"):
            h2: text "HTTP 500 Error"
            if exception.name == "BooruException":
                pre: text exception.msg
            else:
                pre: text "Server error occured"

proc `404`*(): VNode =
    return buildHtml(main):
        section(id="wiki"):
            h2: text "Not Found"
            p: text "The specified page is not found."

proc `403`*(): VNode =
    return buildHtml(main):
        section(id="wiki"):
            h2: text "Forbidden"
            p: text "You don't have enough permissions to do this!"

proc logIn*(rq: Request, errors: seq[ref Exception] = @[]): VNode {.raises: [DbError, IOSelectorsException, KeyError, SodiumError, ValueError].}=
    let newToken = auth.setNewAcsrfToken(
        auth.getSessionIdFrom(rq)
    )
    return buildHtml(main):
        hr: text ""
        ul(id="notifications"):
            for e in errors:
                li: text $(e.msg)
        section(id="wiki"):
            form(action="/login", `method`="post", class="formBox"):
                h2: text "Log in"
                input(hidden=true, type="text", name=antiCsrfFieldName, value=newToken)
                tdiv(class="formRow"):
                    label(`for`=usernameFieldName): text "Username"
                    input(id=usernameFieldName, name=usernameFieldName, type="text", placeholder="PenguinOfDoom")
                tdiv(class="formRow"):
                    label(`for`=passwordFieldName): text "Password"
                    input(id=passwordFieldName, name=passwordFieldName, type="password", placeholder="hunter2")
                input(type="submit", value="Login")
                span:
                    a(href="/signup"): text "Or sign up"

proc signUp*(rq: Request, errors: seq[ref Exception] = @[]): VNode {.raises: [DbError, IOSelectorsException, KeyError, SodiumError, ValueError].}=
    let newToken = auth.setNewAcsrfToken(
        auth.getSessionIdFrom(rq)
    )
    return buildHtml(main):
        hr: text ""
        ul(id="notifications"):
            for e in errors:
                li: text $(e.msg)
        section(id="wiki"):
            form(action="/signup", `method`="post", class="formBox"):
                h2: text "Sign up"
                p: text "Signing up for an account allows you to personalize tag blacklists, among other things."
                input(hidden=true, type="text", name=antiCsrfFieldName, value=newToken)
                tdiv(class="formRow"):
                    label(`for`=usernameFieldName): text "Username"
                    input(id=usernameFieldName, name=usernameFieldName, type="text", placeholder="PenguinOfDoom")
                tdiv(class="formRow"):
                    label(`for`=passwordFieldName): text "Password"
                    input(id=passwordFieldName, name=passwordFieldName, type="password", placeholder="hunter2")
                tdiv(class="formRow"):
                    label(`for`=confirmPasswordFieldName): text "Confirm password"
                    input(id=confirmPasswordFieldName, name=confirmPasswordFieldName, type="password", placeholder="hunter2")
                input(type="submit", value="Sign up")
                span:
                    a(href="/login"): text "Or log in"

proc signUpSuccess*(): VNode =
    return buildHtml(main):
        section(id="wiki"):
            h2: text "Sign up successful!"
            p:
                text "Now that you've signed up, how about you "
                a(href="/login"): text "log in to it"
                text " now?"

proc configPage*(rq: Request): VNode {.raises: [DbError, IOSelectorsException, KeyError, SodiumError, ValueError].} =
    let
        user = auth.getSessionIdFrom(rq).getCurrentUser()
        blist = config.getBlacklistConfig(user.get())
    return buildHtml(main):
        section(id="wiki"):
            form(action="/config", `method`="post", class="formBox"):
                h2: text "Configuration"
                tdiv(class="formRow"):
                    label(`for`=blacklistFieldName): text "Blacklist"
                    textarea(id=blacklistFieldName, name=blacklistFieldName, placeholder="rating:questionable rating:explicit"): text blist
                input(type="submit", value="Save")
