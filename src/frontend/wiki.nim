import karax/[
    karaxdsl, vdom
]
import packages/docutils/rst as rst
import packages/docutils/rstgen as rstgen
import std/strtabs

proc siteWiki*(): VNode =
    return buildHtml(main):
        section(id="wiki"):
            h2: text "Wiki"
            # TODO: markdown and RST conversion here
            p: text "Not available yet!"
