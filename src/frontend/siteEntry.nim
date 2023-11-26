import jester
import karax/[
    karaxdsl, vdom
]
import std/strutils
import packages/docutils/rst as rst
import packages/docutils/rstgen as rstgen
import ../backend/images as images
import ../backend/authentication as auth
import ../settings
import ./params
import ./gallery

proc siteEntry*(img: ImageEntryRef, rq: Request): VNode  =
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
                                    li: a(href="/entry/$#/similar" % $img.id): text "Find similar images"
            section(id="tags"):
                getImageTagsSidebar(img, paramTuple.originalQuery)
                relatedContent(paramTuple.originalQuery)

proc siteEntryEdit*(img: ImageEntryRef): VNode   =
    let mimeMappings = makeMimeMappings()
    return buildHtml(main):
        section(id="image"):
            img(
                src="/images/" & img.hash & "." & mimeMappings[img.formatMime],
                width="500"
            )
            form(class="headerBox", `method`="post"):
                tdiv(class="textAreaAndSubmit"):
                    textarea(
                        name="tags",
                        placeholder="insert_tags_here",
                        id="editTagBox"
                    ): text images.tagsAsString(images.getTagsFor(img))
                    input(type="submit", value="Post")
            tdiv:
                h2: text "Quick tagging guide"
                verbatim rstgen.rstToHtml("""
* **Info** - `author:*`, `character_owner:*`, `character:*`, for each character that shows up.
* **Rating** - `rating`: `safe`, `questionable` or `explicit`.
* **Videos** - use `meta:animated`. If sound is present, add `meta:sound`. Could also add `meta:mp4`/`meta:gif`/`meta:webm`, ...
* **Composition** - `1female`, `1male`, `2female`, ...
* **Clothing**
* **Actions**
* **Body/face features**
* **Tag-what-else-you-see!** Favor more frequent tags.
""", {rst.roSupportMarkdown, rst.roPreferMarkdown}, newStringTable(modeStyleInsensitive))

proc siteEntryConfirmDelete*(img: ImageEntryRef): VNode   =
    let mimeMappings = makeMimeMappings()
    return buildHtml(main):
        section(id="image"):
            img(
                src="/images/" & img.hash & "." & mimeMappings[img.formatMime],
                width="400"
            )
            h2: text "Confirm deletion"
            form(class="headerBox", `method`="post"):
                tdiv(class="textAreaAndSubmit"):
                    tdiv:
                        text "Press the button to confirm deletion → "
                        input(type="submit", value="Delete")
                    span:
                        text "Otherwise, click the Back button on your browser to cancel."
