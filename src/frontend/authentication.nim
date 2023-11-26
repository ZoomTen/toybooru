import jester
import karax/[
    karaxdsl, vdom
]
import ../backend/authentication as auth
import ../settings

proc logIn*(rq: Request, errors: seq[ref Exception] = @[]): VNode =
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
                tdiv:
                    input(id=rememberFieldName, name=rememberFieldName, type="checkbox")
                    label(`for`=rememberFieldName): text "Keep me signed in until I log out"
                input(type="submit", value="Login")
                span:
                    a(href="/signup"): text "Or sign up"

proc signUp*(rq: Request, errors: seq[ref Exception] = @[]): VNode =
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
