import jester
import karax/[
    karaxdsl, vdom
]
import ../backend/authentication as auth
import ../backend/userConfig as config
import ../settings

proc configPage*(rq: Request): VNode  =
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
