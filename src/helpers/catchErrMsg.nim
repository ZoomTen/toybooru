import results
export results

template catchErrMsg*(body: typed): Result[type(body), string] =
    ## Catch *any* exception for `body` and store only the message.
    ## `catch` only covers `CatchableError`, and a lot of things in Nim
    ## do not inherit from it, instead directly from `Exception`.
    type R = Result[type(body), string]
    try:
        when type(body) is void:
            body
            R.ok()
        else: R.ok(body)
    except Exception as e:
        R.err(e.msg)
