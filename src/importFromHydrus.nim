import ./backend/setup as setup
import ./backend/upload as upload
import std/[
    os, mimetypes, strutils, sugar
]

{.push raises: [].}

when isMainModule:
    var args = commandLineParams()
    let mimes = newMimetypes()
    if args.len == 1:
        if dirExists(args[0]):
            setup.folders()
            setup.imageTable()
            setup.tagTable()
            for file in walkDir(args[0]):
                var (dir, name, ext) = splitFile(file.path)

                if ext == ".txt":
                    continue

                debugEcho name

                let something = collect:
                    for line in lines(file.path & ".txt"):
                        line.replace(" ", "_")

                var myfile = upload.newFileUploadRef(
                    file.path.readFile(), file.path.getFileSize().int,
                    name & ext, mimes.getMimetype(ext)
                )

                processFile(
                    myfile, something.join(" ")
                )
    else:
        debugEcho "Usage: ./importFromHydrus <hydrus export directory>"
        debugEcho ""
        debugEcho "Select some images, right-click, Share -> Export -> Files"
        debugEcho "**Make sure 'export tags to .txt files' is checked!!**"
