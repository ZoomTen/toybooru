type
    BooruException* = object of CatchableError
    TokenException* = object of ValueError
    LoginException* = object of ValueError
    ValidationError* = object of ValueError
