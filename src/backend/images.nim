import ../settings
import std/[
    strutils, sugar
]
import ./validation as validate
import ./exceptions

# db stuff, change for 2.0.0
import std/db_sqlite

import chronicles as log

type
    ImageEntryRef* = ref object
        id*: int
        hash*, formatMime*: string
        dimensions*: tuple[width, height: int]
    TagTuple* = tuple
        tag: string
        count: int

{.push raises:[].}

## Get query as a sequence of ImageEntryRef, must match the column *order*
## of the images table.
proc getQueried*(query: string, args: varargs[string]): seq[ImageEntryRef] {.raises:[DbError, ValueError].}=
    result = @[]
    let db = open(dbFile, "", "", "")
    defer: db.close()

    for row in db.instantRows(query.sql(), args):
        result.add(
            ImageEntryRef(
                id: row[0].parseInt(),
                hash: row[1],
                formatMime: row[2],
                dimensions: (
                    row[3].parseInt(),
                    row[4].parseInt()
                )
            )
        )

## Int is for ImageEntryRef id's
#[
    With
        include_and As ( -- Collect all non-prefixed tags by an AND relation
            With
                itag1 As (Select image_id From image_tags Where tag_id = 3),
                ...
            Select image_tags.image_id From image_tags
                Inner Join itag1 On image_tags.image_id = tag1.image_id
                ...
            Group By image_tags.image_id
        ) ,
        exclude_or As ( -- Collect all tags prefixed with - by an OR relation
            With
                xtags As (Select image_id From image_tags Where tag_id = In (5,..))
            Select image_tags.image_id From image_tags
                Right Join xtags On image_tags.image_id = xtags.image_id
            Group By image_tags.image_id
        )
    Select images.* From include_and
    Inner Join images On image_id = images.id
    Where image_id Not In exclude_or
]#
proc buildTagQuery*(includes, excludes: seq[int] = @[]): string {.raises: [ValueError].}=
    log.logScope:
        topics = "buildTagQuery"

    var query: string

    log.debug("Query building",
              includes = includes,
              excludes = excludes,
              includeCount = includes.len(),
              excludeCount = excludes.len()
              )

    if includes.len() < 1:
        query = "With include_and As ( Select image_id From image_tags Group By image_id )" # all of them
    else:
        # Collect all non-prefixed tags by an AND relation as including terms
        query = "With include_and As ( With "
        let includesTagId = collect:
            for qIndex, tagId in includes:
                "itag$# As (Select image_id From image_tags Where tag_id = $#)" % [
                    $qIndex, $tagId
                ]
        query &= includesTagId.join(",")
        query &= " Select image_tags.image_id From image_tags"
        for qIndex, tagId in includes:
            query &= " Inner Join itag$# On image_tags.image_id = itag$#.image_id" % [
                $qIndex, $qIndex
            ]
        query &= " Group By image_tags.image_id )"

    # Collect all tags prefixed with - by an OR relation as excluding terms
    if excludes.len() >= 1:
        query &= ", exclude_or As ( With "
        query &= "xtags As ( Select image_id From image_tags Where tag_id In ("
        let excludesTagId = collect:
            for qIndex, tagId in excludes:
                $tagId
        query &= excludesTagId.join(",")
        query &= "))"
        query &= " Select image_tags.image_id From image_tags"
        query &= " Right Join xtags On image_tags.image_id = xtags.image_id"
        query &= " Group By image_tags.image_id )"

    query &= " Select images.* From include_and Inner Join images On image_id = images.id"

    if excludes.len() >= 1:
        query &= " Where image_id Not In exclude_or"

    log.debug(
        "Resulting query",
        query = query
        )
    return query

# https://gist.github.com/ssokolow/262503
proc buildPageQuery*(
        query: string,
        pageNum, numResults: int,
        descending: bool = false
    ): string =
        log.logScope:
            topics = "buildPageQuery"

        if query == "": # blank query
            return query

        result = "With root_query As ( " & query & " ) "
        result &= "Select * From root_query Where id Not In "
        if descending:
            result &= "( Select id From root_query Order By id Desc Limit " & $(numResults * pageNum) & ")"
            result &= "Order By id Desc Limit " & $numResults
        else:
            result &= "( Select id From root_query Order By id Asc Limit " & $(numResults * pageNum) & ")"
            result &= "Order By id Asc Limit " & $numResults

        log.debug(
            "Transformed query to pagination query",
            query=query,
            finalQuery=result,
            pageNum=pageNum,
            numResults=numResults,
            descending=descending
        )

proc getCountOfQuery*(query: string): int  {.raises:[DbError, ValueError].}=
    if query == "":
        return 0

    let db = open(dbFile, "", "", "")
    defer: db.close()
    var cxquery = "With root_query As ( " & query & " ) "
    cxquery &= "Select Count(1) From root_query"
    return db.getValue(cxquery.sql()).parseInt()

proc getMostPopularTagsGeneral*(numberOfTags: int = 10): seq[TagTuple]  {.raises:[DbError, ValueError].}=
    result = @[]
    let db = open(dbFile, "", "", "")
    defer: db.close()

    for row in db.instantRows(sql"Select tag, count From tags Order By count Desc Limit ?", numberOfTags):
        result.add(
            (tag: row[0], count: row[1].parseInt())
        )

proc getRandomIdFrom*(query: string): int  {.raises:[DbError, ValueError].}=
    let db = open(dbFile, "", "", "")
    defer: db.close()
    var cxquery = "With root_query As ( " & query & " ) "
    cxquery &= "Select id From root_query Order By Random() Limit 1"
    return db.getValue(cxquery.sql()).parseInt()

proc getTagsFor*(image: ImageEntryRef): seq[TagTuple]  {.raises:[DbError, ValueError].}=
    let db = open(dbFile, "", "", "")
    defer: db.close()

    result = @[]

    for row in db.instantRows(
        sql"""
            Select tags.tag, tags.count From image_tags
            Inner Join tags On image_tags.tag_id = tags.id
            Where image_tags.image_id = ?
        """, $image.id
    ):
        result.add(
            (tag: row[0], count: row[1].parseInt())
        )

proc getAllTags*(): seq[TagTuple]  {.raises:[DbError, ValueError].}=
    let db = open(dbFile, "", "", "")
    defer: db.close()

    result = @[]

    for row in db.instantRows(sql"Select tag, count From tags Order By tag Asc"):
        result.add(
            (tag: row[0], count: row[1].parseInt())
        )

proc tagsAsString*(tags: seq[TagTuple]): string =
    var st: seq[string]
    for tag in tags:
        st.add(tag.tag)
    return st.join(" ")

proc buildSearchQuery*(
        query: string = "",
        pageNum:int = 0,
        numResults:int = defaultNumResults
    ): string {.raises:[DbError, ValueError].}=
        log.logScope:
            topics = "buildSearchQuery"

        log.debug("Query input", query=query)

        if query.strip() == "":
            log.debug("Empty query, selecting all images")
            return "Select * From images"

        var
            includes: seq[int] = @[]
            excludes: seq[int] = @[]

        let db = open(dbFile, "", "", "")
        defer: db.close()

        for q in query.split(" "):
            var queryElement = q.strip()
            if queryElement == "": continue
            if queryElement[0] == '-':
                queryElement = queryElement.substr(1)
                log.debug("Negating keyword", keyword=queryElement)
                try:
                    excludes.add(
                        db.getValue(
                            sql"Select id From tags Where tag = ?",
                            queryElement
                        ).parseInt()
                    )
                except ValueError:
                    log.debug("Keyword not found", keyword=queryElement)
                    discard
            else:
                log.debug("Adding keyword", keyword=queryElement)
                try:
                    includes.add(
                        db.getValue(
                            sql"Select id From tags Where tag = ?",
                            queryElement
                        ).parseInt()
                    )
                except ValueError:
                    log.debug("Keyword not found", keyword=queryElement)
                    discard

        if includes.len() == 0 and excludes.len() == 0:
            # if there are no matches, just say so
            log.debug("No matches, returning empty query")
            return ""

        return images.buildTagQuery(includes=includes, excludes=excludes)

# TODO: prone to SQL injection
proc getTagAutocompletes*(keyword: string): seq[TagTuple] {.raises:[DbError, ValueError].} =
    log.logScope:
        topics = "getTagAutocompletes"

    let db = open(dbFile, "", "", "")
    defer: db.close()

    result = @[]

    try:
        let kw = validate.sanitizeKeyword(keyword)
        # need keyword sanitization
        for row in db.instantRows(
            sql("Select tag, count From tags Where tag Like \"%" & kw & "%\" Order By tag Asc")
        ):
            result.add(
                (tag: row[0], count: row[1].parseInt())
            )
    except ValidationError:
        log.debug("Keyword invalid", keyword=keyword)
        return result
