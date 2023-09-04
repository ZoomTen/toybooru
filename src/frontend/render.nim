import jester
import karax/[
    karaxdsl, vdom
]
import std/[
    strutils, math, sequtils, algorithm
]
import ../backend/images as images
import ../backend/validation as validate
import ../settings

import std/db_sqlite

import chronicles as log

{.push raises: [].}

type
    PageVars* = tuple
        query: string ## contains raw query!
        pageNum: int
        numResults: int

proc getVarsFromParams*(params: Table): PageVars =
    result.query = params.getOrDefault("q")
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

proc getImageTagsOfListSidebar*(params: Table): VNode {.raises: [DbError, ValueError].} =
    log.logScope:
        topics = "getImageTagsOfListSidebar"

    log.debug("Get image tags to sidebar")

    let
        paramTuple = params.getVarsFromParams
        pageNum = paramTuple.pageNum
        numResults = paramTuple.numResults
    var
        query = ""
        imageList: seq[ImageEntryRef] = @[]
    try:
        if paramTuple.query.strip() != "":
            query = validate.sanitizeQuery(paramTuple.query)
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
                tagEntry.toTagDisplay(query)
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

proc siteHeader(query: string = ""): VNode =
    return buildHtml(header):
        nav(id="mainMenu"):
            tdiv(id="titleAndSearch"):
                h1: text siteName
                form(class="inputAndSubmit", action="/list", `method`="get"):
                    input(type="search", name="q", autocomplete="off", placeholder="find some_tags", id="searchInput", value=query)
                    input(type="submit", value="Find")
                ul(class="hidden"):
                    li:
                        a(href="#"): text "Skip navigation"
                    li:
                        a(href="#"): text "Skip to tags"
            ul(class="navLinks", id="headerLinks"):
                li:
                    a(href="/"): text "Front page"
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
            "&count=" & $numResults & "&q="
        else:
            "&q="

    return buildHtml(nav(id="pageNav")):
        h2(class="hidden"): text "Pages"
        ul(class="navLinks"):
            # prev/first
            if pageNum == 0:
                li(aria-label="First"): text "<<"
                li(aria-label="Prev"): text "<"
            else:
                li: a(aria-label="First", href="?page=0" & appendParam & query): text "<<"
                li: a(aria-label="Prev", href="?page=" & $(pageNum-1) & appendParam & query): text "<"

            # page numbers, show 2 pages around current page
            for i in 0..<numPages:
                if i in pageNum-2..pageNum+2:
                    if i == pageNum:
                        li: text $(i+1)
                    else:
                        li: a(href="?page=" & $i & appendParam & query): text $(i+1)

            # next/last
            if pageNum == numPages-1:
                li(aria-label="Next"): text ">"
                li(aria-label="Last"): text ">>"
            else:
                li: a(aria-label="Next", href="?page=" & $(pageNum+1) & appendParam & query): text ">"
                li: a(aria-label="Last", href="?page=" & $(numPages-1) & appendParam & query): text ">>"

proc buildGallery(imageList: seq[ImageEntryRef], query: string): VNode {.raises: [DbError, ValueError].} =
    return buildHtml(ul(class="galleryItems navLinks")):
        for img in imageList:
            li:
                a(href="/entry/" & $img.id & "?q="&query): img(
                        src="/thumbs/" & img.hash & ".jpg",
                        title=images.tagsAsString(
                            images.getTagsFor(img)
                        )
                    )

proc siteList*(params: Table): VNode  {.raises: [DbError, ValueError].} =
    log.logScope:
        topics = "siteList"

    log.debug("Get images to gallery display")

    let
        paramTuple = params.getVarsFromParams
        pageNum = paramTuple.pageNum
        numResults = paramTuple.numResults
    var
        query = ""
        imageList: seq[ImageEntryRef] = @[]
        numPages = 0
    try:
        if paramTuple.query.strip() != "":
            query = validate.sanitizeQuery(paramTuple.query)
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
                    imageList.buildGallery(query)
                    numPages.buildGalleryPagination(pageNum, numResults, query)
            section(id="tags"):
                uploadForm()
                if imageList.len >= 1:
                    getImageTagsOfListSidebar(params)
                    relatedContent(query)

proc siteUntagged*(params: Table): VNode {.raises: [DbError, ValueError].} =
    let
        paramTuple = params.getVarsFromParams
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

proc siteEntry*(img: ImageEntryRef, query: string): VNode {.raises: [DbError, KeyError, ValueError].} =
    let
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
                    tdiv:
                        dt: text "Actions"
                        dd:
                            ul:
                                li: a(href="/entry/$#/edit" % $img.id): text "Edit"
                                li: a(href="/entry/$#/delete" % $img.id): text "Delete"
            section(id="tags"):
                getImageTagsSidebar(img, query)
                relatedContent(query)

proc siteEntryEdit*(img: ImageEntryRef): VNode  {.raises: [DbError, ValueError].} =
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

proc siteAllTags*(params: Table): VNode {.raises: [DbError, ValueError].} =
    let (query, pageNum, numResults) = params.getVarsFromParams
    let tags = images.getAllTags()
    return buildHtml(main):
        section(id="wiki"):
            h2: text "All tags"
            ul(id="allTags", class="navLinks"):
                for tagEntry in tags:
                    tagEntry.toTagDisplay(query)

proc masterTemplate*(title: string = "", params: Table, siteContent: VNode): string =
    let (query, pageNum, numResults) = params.getVarsFromParams
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
                    siteHeader(query)
                    siteContent
                footer:
                    text "© 2023 Zumi. Source code is available "
                    a(href=sourceLink): text "here"
                    text "."
                script(src="/assets/autocomplete.js")
    return "<!DOCTYPE html>\n" & $vn

proc landingPage*(): string {.raises: [ValueError, DbError].}=
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
                        siteHeader()
                        main:
                            p(class="landingStats"): text "Browse through $# images" % [($postCount).insertSep(',')]
                footer:
                    text "© 2023 Zumi. Source code is available "
                    a(href=sourceLink): text "here"
                    text "."
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
            h2: text "HTTP 404 Not Found"
            p: text "The specified page is not found."
