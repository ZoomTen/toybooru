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
