import jester
import karax/[
    karaxdsl, vdom
]
import std/[
    strutils, math, algorithm
]
import ../backend/images as images
import ../backend/validation as validate
import ../backend/authentication as auth
import ../backend/userConfig as config
import ../settings
import ../importDb
import ./params

import chronicles as log

proc genericMakeTagText(tagGet: TagTuple): VNode  =
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

proc toTagDisplay(tagEntry: TagTuple, query: string = ""): VNode  =
    let q = query.strip()
    return buildHtml(li):
        a(href="/list?q="&q&"+"&tagEntry.tag, title="add to search"): text "+"
        text " "
        a(href="/list?q="&q&"+-"&tagEntry.tag, title="exclude from search"): text "-"
        text " "
        a(href="/wiki/$#" % tagEntry.tag, title="boot up wiki page"): text "?"
        text " "
        genericMakeTagText tagEntry

proc getPopularTagsSidebar(): VNode =
    var popularTags = images.getMostPopularTagsGeneral(25)
    popularTags.sort(compareTags)
    return buildHtml(nav):
        h2: text "Popular tags"
        ul(id="navTags", class="navLinks"):
            for tagEntry in popularTags:
                tagEntry.toTagDisplay
        # a(href="#"): text "View all tags"

proc getImageTagsSidebar*(img: ImageEntryRef, query: string=""): VNode =
    let tags = images.getTagsFor(img)
    return buildHtml(nav):
        if tags.len > 0:
            h2: text "Tags in image"
            ul(id="navTags", class="navLinks"):
                for tagEntry in tags:
                    tagEntry.toTagDisplay(query)
        a(href="/taglist"): text "View all tags"

proc getImageTagsOfListSidebar*(rq: Request, imageList: seq[ImageEntryRef]): VNode  =
    log.logScope:
        topics = "getImageTagsOfListSidebar"

    log.debug("Get image tags to sidebar")

    let
        params = rq.params
        paramTuple = params.getVarsFromParams(auth.getSessionIdFrom(rq).getCurrentUser())
        pageNum = paramTuple.pageNum
        numResults = paramTuple.numResults
    var
        query = ""
        userQuery = ""
    try:
        if paramTuple.query.strip() != "":
            query = validate.sanitizeQuery(paramTuple.query)
        if paramTuple.originalQuery.strip() != "":
            userQuery = validate.sanitizeQuery(paramTuple.originalQuery)
    except ValueError as e:
        log.debug("Invalid query", query=paramTuple.query)

    var totalTags: seq[TagTuple] = images.getTagsForMultiple(imageList)

    return buildHtml(nav(class="headerBox")):
        h2: text "Tags for images in list"
        ul(id="navTags", class="navLinks"):
            for tagEntry in totalTags:
                tagEntry.toTagDisplay(userQuery)
        a(href="/taglist"): text "View all tags"

proc relatedContent*(query: string = "", shouldShowRandomPics: bool = true): VNode =
    return buildHtml(aside):
        h2: text "Related"
        ul(class="navLinks", id="galleryLinks"):
            if shouldShowRandomPics:
                if query.strip == "":
                    li: a(href="/random"): text "Random pic"
                else:
                    li: a(href="/random?q="&query): text "Random pic from this query"
            li: a(href="/untagged"): text "View untagged posts"

proc uploadForm(rq: Request): VNode =
    let newToken = auth.setNewAcsrfToken(
        auth.getSessionIdFrom(rq)
    )
    return buildHtml(
        form(class="formBox",
             action="/upload",
             `method`="post",
             enctype="multipart/form-data")
        ):
            h2:
                text "Upload"
            input(name="data", type="file")
            input(hidden=true, type="text", name=antiCsrfFieldName, value=newToken)
            tdiv(class="textAreaAndSubmit"):
                textarea(name="tags",
                         placeholder="tag_me and_stuff yo",
                         id="submitTagBox"
                )
                input(type="submit")

proc buildGalleryPagination(numPages, pageNum, numResults: int, query: string = ""): VNode =
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

proc buildGallery(imageList: seq[ImageEntryRef], query: string = ""): VNode  =
    let queryAddition = if query.strip() != "":
                "?q=" & query
            else: ""
    return buildHtml(ul(class="galleryItems navLinks")):
        for img in imageList:
            li:
                when defined(usePostgres):
                    # TODO: make a DB function to represent concat'd tags as a column of strings
                    a(href="/entry/" & $img.id & queryAddition): img(
                            src="/thumbs/" & img.hash & ".jpg"
                        )
                else:
                    a(href="/entry/" & $img.id & queryAddition): img(
                            src="/thumbs/" & img.hash & ".jpg",
                            title=images.tagsAsString(
                                images.getTagsFor(img)
                            )
                        )

proc siteList*(rq: Request): VNode   =
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
        log.debug("Count number of pages")
        numPages = ceilDiv(
            images.getCountOfQuery(imgSqlQuery),
            numResults
        )
        log.debug("Get image list")
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
                    uploadForm(rq)
                if imageList.len >= 1:
                    getImageTagsOfListSidebar(rq, imageList)
                relatedContent(userQuery, (imageList.len >= 1))

proc siteUntagged*(rq: Request): VNode  =
    let
        params = rq.params
        paramTuple = params.getVarsFromParams(auth.getSessionIdFrom(rq).getCurrentUser())
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
                    imageList.buildGallery()
                    numPages.buildGalleryPagination(pageNum, numResults)

proc siteSimilar*(rq: Request, img: images.ImageEntryRef): VNode  =
    let
        params = rq.params
        paramTuple = params.getVarsFromParams(auth.getSessionIdFrom(rq).getCurrentUser())
        maxDistance = paramTuple.distance
        pageNum = paramTuple.pageNum
        numResults = paramTuple.numResults
        imgSqlQuery = images.buildImageSimilarityQuery(img, maxDistance)
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
                h2: text "Similar images (max distance = " & $maxDistance & ")"
                form(`method`="get", class="formSingleEntry"):
                    label(`for`="distanceSpinbox"): text "Try again with distance"
                    input(id="distanceSpinbox", name="distance", type="number", min="0", max="64", value = $(maxDistance)): discard
                    input(type="submit")
                imageList.buildGallery()
                numPages.buildGalleryPagination(pageNum, numResults)

proc siteAllTags*(rq: Request): VNode  =
    let (query, originalQuery, pageNum, numResults, distance) = rq.params.getVarsFromParams(
        auth.getSessionIdFrom(rq).getCurrentUser()
    )
    let tags = images.getAllTags()
    return buildHtml(main):
        section(id="wiki"):
            h2: text "All tags"
            ul(id="allTags", class="navLinks"):
                for tagEntry in tags:
                    tagEntry.toTagDisplay(query)
