import karax/[
    karaxdsl, vdom
]

proc siteWiki*(): VNode =
    return buildHtml(main):
        section(id="wiki"):
            h2: text "Wiki"
            # TODO: markdown and RST conversion here
            p: text "Not available yet!"
