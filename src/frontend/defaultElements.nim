import jester
import karax/[
    karaxdsl, vdom
]
import ../backend/authentication as auth
import ./params
import ../settings
import ../backend/images as images
import std/strutils

proc siteHeader(rq: Request): VNode  =
    let user = auth.getSessionIdFrom(rq).getCurrentUser()
    let (query, originalQuery, pageNum, numResults, distance) = rq.params.getVarsFromParams(user)
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



proc landingPage*(rq: Request): string =
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

proc masterTemplate*(title: string = "", rq: Request, siteContent: VNode): string =
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
