import chronicles as log
import karax/[
    karaxdsl, vdom
]

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
