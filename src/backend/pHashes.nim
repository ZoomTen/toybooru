import stb_image/read as stbr
import ../stb/resize as stbz
import arraymancer as mancer
import ../helpers/fft
import std/sequtils, std/sugar
import ../settings
import std/strutils
import chronicles as log

proc pHash*(imageFileContents: string): BiggestInt =
    result = 0
    var
        xSize: int
        ySize: int
        channels: int
    let
        resizedImage = stbr.loadFromMemory(
            cast[seq[uint8]](imageFileContents), xSize, ySize, channels, stbr.Grey
        ).resize(
            xSize, ySize, 32, 32, stbr.Grey
        ).map(x => x.float64)

    let mtx = mancer.toTensor(resizedImage).reshape(32,32)

    # make 2D DCT by first operating a 1D DCT on rows then columns
    var dctMtx = newTensor[float64](32, 32)

    # dct rows
    for i in 0..<mtx.shape[1]:
        dctMtx[i, 0..<mtx.shape[0]] = mtx[i, 0..<mtx.shape[0]].dct()

    # dct columns
    dctMtx = dctMtx.transpose()
    for i in 0..<dctMtx.shape[1]:
        dctMtx[i, 0..<dctMtx.shape[0]] = dctMtx[i, 0..<dctMtx.shape[0]].dct()

    # get only the top left 8x8 frequencies
    dctMtx = dctMtx.transpose()[0..<8, 0..<8]

    # turn into true/false map
    let median = dctMtx.reshape(64).percentile(50)
    let newImageDct = dctMtx.map(x => (x > median)).reshape(64)

    # turn into hash
    for i in 0..<64:
        if newImageDct[i]:
            result += 1
        if i < 63:
            result = result shl 1

    # blank white image has the hash of 1000000..
    # so discard that
    if result == (1 shl 63):
        result = 0

