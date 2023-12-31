when defined(usePostgres):
    when NimMajor > 1:
        import db_connector/db_postgres
    else:
        import std/db_postgres
    export db_postgres
else:
    when NimMajor > 1:
        import db_connector/db_sqlite
    else:
        import std/db_sqlite
    export db_sqlite

import results
export results

import ./settings

template withSessionDb*(body: untyped) =
    try:
        let sessDb {.inject.} = open(sessionDbUrl, sessionDbUser, sessionDbPass, sessionDbDatabase)
        when not defined(usePostgres):
            sessDb.exec(sql"PRAGMA foreign_keys = ON")
        try:
            `body`
        finally:
            sessDb.close()
    except DbError as e:
        when defined(release) or defined(danger):
            return err("Database error")
        else:
            return err(e.msg)

template withMainDb*(body: untyped) =
    try:
        let mainDb {.inject.} = open(mainDbUrl, mainDbUser, mainDbPass, mainDbDatabase)
        try:
            `body`
        finally:
            mainDb.close()
    except DbError as e:
        when defined(release) or defined(danger):
            return err("Database error")
        else:
            return err(e.msg)
