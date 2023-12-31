import stb_image/read as stbr
import ../stb/resize as stbz
import arraymancer as mancer
import ../helpers/fft
import std/sequtils, std/sugar

import results
export results

{.push raises:[].}

type
    PhashResult = Result[BiggestInt, string]

proc pHash*(imageFileContents: string): PhashResult =
    var
        xSize: int
        ySize: int
        channels: int
        resizedImage: seq[float64]
        mtx: Tensor[float64]
        newImageDct: Tensor[bool]
        finalHash = 0
    try:
        resizedImage = stbr.loadFromMemory(
            cast[seq[uint8]](imageFileContents), xSize, ySize, channels, stbr.Grey
        ).resize(
            xSize, ySize, 32, 32, stbr.Grey
        ).map(x => x.float64)
    except STBIException as e:
        return PhashResult.err("Cannot instantiate resized image: " & e.msg)

    try:
        mtx = mancer.toTensor(resizedImage).reshape(32,32)
    except ValueError as e:
        return PhashResult.err("Cannot reshape image array: " & e.msg)

    # make 2D DCT by first operating a 1D DCT on rows then columns
    var dctMtx = newTensor[float64](32, 32)

    # dct rows
    for i in 0..<mtx.shape[1]:
        try:
            dctMtx[i, 0..<mtx.shape[0]] = mtx[i, 0..<mtx.shape[0]].dct()
        except ValueError as e:
            return PhashResult.err("Cannot transform phash DCT rows: " & e.msg)

    # dct columns
    dctMtx = dctMtx.transpose()
    for i in 0..<dctMtx.shape[1]:
        try:
            dctMtx[i, 0..<dctMtx.shape[0]] = dctMtx[i, 0..<dctMtx.shape[0]].dct()
        except ValueError as e:
            return PhashResult.err("Cannot transform phash DCT columns: " & e.msg)

    # get only the top left 8x8 frequencies
    dctMtx = dctMtx.transpose()[0..<8, 0..<8]

    # turn into true/false map
    try:
        let median = dctMtx.reshape(64).percentile(50)
        newImageDct = dctMtx.map(x => (x > median)).reshape(64)
    except ValueError as e:
        return PhashResult.err("Cannot determine phash bitmap: " & e.msg)

    # turn into hash
    for i in 0..<64:
        if newImageDct[i]:
            finalHash += 1
        if i < 63:
            finalHash = finalHash shl 1

    # blank white image has the hash of 1000000..
    # so discard that
    if finalHash == (1 shl 63):
        finalHash = 0

    return PhashResult.ok(finalHash)

