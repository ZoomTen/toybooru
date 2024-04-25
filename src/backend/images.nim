import ../settings
import std/[
    strutils, sugar
]
import ./validation as validate
import ./exceptions
import ../importDb

when not defined(usePostgres):
    import ../helpers/sqliteLoadExt

import chronicles as log

type
    ImageEntryRef* = ref object
        id*: int
        hash*, formatMime*: string
        dimensions*: tuple[width, height: int]
    TagTuple* = tuple
        tag: string
        count: int

## Get query as a sequence of ImageEntryRef, must match the column *order*
## of the images table.
proc getQueried*(query: string, args: varargs[string]): seq[ImageEntryRef] =
    result = @[]

    withMainDb:
        when not defined(usePostgres):
            assert mainDb.enableExtensions() == 0, "Failed to enable sqlite extensions"
            assert mainDb.loadExtension("./popcount") == 0, "Failed to load popcount extension"

        log.debug("Get query as images", query=query)

        if query.strip() == "":
            return result

        for row in mainDb.instantRows(query.sql(), args):
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
proc buildTagQuery*(includes: seq[string] = @[], excludes: seq[string] = @[]): string =
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
                "itag$# As (Select image_id From image_tags Where tag_id = (Select id From tags Where tag = '$#'))" % [
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
        query &= "( Select id From tags Where tag In ("
        let excludesTagId = collect:
            for qIndex, tagId in excludes:
                "'" & $tagId & "'"
        query &= excludesTagId.join(",")
        query &= "))"
        query &= "))"
        query &= " Select image_tags.image_id From image_tags"
        query &= " Right Join xtags On image_tags.image_id = xtags.image_id"
        query &= " Group By image_tags.image_id )"

    query &= " Select images.* From include_and Inner Join images On image_id = images.id"

    if excludes.len() >= 1:
        # sqlite is fine with "Not In <aliased subquery>"
        # but postgres seems to require me to spell it out by "Not In (Select <a column> From <aliased subquery>)"
        query &= " Where image_id Not In (Select image_id From exclude_or)"

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

proc getCountOfQuery*(query: string): int  =
    if query == "":
        return 0

    withMainDb:
        when not defined(usePostgres):
            assert mainDb.enableExtensions() == 0, "Failed to enable sqlite extensions"
            assert mainDb.loadExtension("./popcount") == 0, "Failed to load popcount extension"

        var cxquery = "With root_query As ( " & query & " ) "
        cxquery &= "Select Count(*) From root_query"
        return mainDb.getValue(cxquery.sql()).parseInt()

proc getMostPopularTagsGeneral*(numberOfTags: int = 10): seq[TagTuple]  =
    result = @[]

    withMainDb:
        for row in mainDb.instantRows(
            sql"Select tag, count From tags Order By count Desc Limit ?",
            numberOfTags
        ):
            result.add(
                (tag: row[0], count: row[1].parseInt())
            )

proc getRandomIdFrom*(query: string): int  =
    var cxquery = "With root_query As ( " & query & " ) "
    cxquery &= "Select id From root_query Order By Random() Limit 1"

    withMainDb:
        return mainDb.getValue(cxquery.sql()).parseInt()

proc getTagsFor*(image: ImageEntryRef): seq[TagTuple]  =
    result = @[]

    withMainDb:
        for row in mainDb.instantRows(
            sql"""
                Select tags.tag, tags.count From image_tags
                Inner Join tags On image_tags.tag_id = tags.id
                Where image_tags.image_id = ?
            """, $image.id
        ):
            result.add(
                (tag: row[0], count: row[1].parseInt())
            )

proc getTagsForMultiple*(images: seq[ImageEntryRef], sorted: bool = true): seq[TagTuple] =
    result = @[]
    
    if images.len == 0:
        return result
    
    # build query
    var query = """
        Select tags.tag, tags.count From image_tags
        Inner Join tags On image_tags.tag_id = tags.id
        Where image_tags.image_id In (
    """
    for i in 0..<images.len: # assume that ID is always gonna be a number
        query &= $(images[i].id)
        if i < (images.len - 1):
            query &= ","
    query &= ")"
    if sorted: # deduplicated and sorted
        query &= "Group By tag, count Order By tag Asc"

    #execute it
    withMainDb:
        for row in mainDb.instantRows(query.sql):
            result.add(
                (tag: row[0], count: row[1].parseInt())
            )

proc getAllTags*(): seq[TagTuple]  =
    result = @[]

    withMainDb:
        for row in mainDb.instantRows(
            sql"Select tag, count From tags Order By tag Asc"
        ):
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
): string =
    log.debug("Query input", query=query)

    if query.strip() == "":
        log.debug("Empty query, selecting all images")
        return "Select * From images"

    var
        includes: seq[string] = @[]
        excludes: seq[string] = @[]

    for q in query.split(" "):
        var queryElement = q.strip()
        if queryElement == "": continue
        if queryElement[0] == '-':
            queryElement = queryElement.substr(1)
            try:
                queryElement = validate.sanitizeKeyword(queryElement)
            except ValidationError:
                log.debug("Keyword invalid", keyword=queryElement)
                continue

            log.debug("Negating keyword", keyword=queryElement)
            excludes.add(queryElement)
        else:
            try:
                queryElement = validate.sanitizeKeyword(queryElement)
            except ValidationError:
                log.debug("Keyword invalid", keyword=queryElement)
                continue

            log.debug("Adding keyword", keyword=queryElement)
            includes.add(queryElement)
    #[
    if includes.len() == 0 and excludes.len() == 0:
        # if there are no matches, just say so
        log.debug("No matches, returning empty query")
        return ""
    ]#
    log.debug("Resulting arrray", includes, excludes)
    return images.buildTagQuery(includes=includes, excludes=excludes)

# TODO: prone to SQL injection
proc getTagAutocompletes*(keyword: string): seq[TagTuple]  =
    result = @[]

    try:
        let kw = validate.sanitizeKeyword(keyword)
        # need keyword sanitization

        withMainDb:
            for row in mainDb.instantRows(
                sql("Select tag, count From tags Where tag Like '%" & kw & "%' Order By tag Asc")
            ):
                result.add(
                    (tag: row[0], count: row[1].parseInt())
                )
    except ValidationError:
        log.debug("Keyword invalid", keyword=keyword)
        return result

proc buildImageSimilarityQuery*(image: ImageEntryRef, maxDistance: int = 64): string =
    when defined(usePostgres):
        return """
            Select id, hash, format, width, height From (
                Select image_id, bit_count(((comparator | phash) - (comparator & phash))::bit(64)) as distance From
                    (Select phash As comparator From image_phashes Where image_id = """ & $(image.id) & """) As compare_images
                    Cross Join image_phashes
            ) As most_similar
            Left Join images on image_id = images.id Where distance < """ & $maxDistance & """ Order by distance Asc
        """
    else:
        return """
            Select id, hash, format, width, height From (
                Select image_id, popcount((comparator | phash) - (comparator & phash)) as distance From
                    (Select phash As comparator From image_phashes Where image_id = """ & $(image.id) & """)
                    Cross Join image_phashes
            ) Left Join images on image_id = images.id Where distance < """ & $maxDistance & """ Order by distance Asc
        """
