# This is an ad-hoc implementation

import stb_image/components
export components.Y
export components.YA
export components.RGB
export components.RGBA

from stb_image/read import STBIException

when defined(windows) and defined(vcc):
  {.pragma: stbcall, stdcall.}
else:
  {.pragma: stbcall, cdecl.}

# Include the header
{.compile: "resize.c".}

when defined(Posix) and not defined(haiku):
  {.passl: "-lm".}

# Internal functions

proc stbir_resize_uint8(
  input_pixels: pointer,
  in_w, in_h: cint,
  in_stride: int,
  output_pixels: pointer,
  out_w, out_h: cint,
  out_stride: int,
  num_channels: int
): cint
  {.importc: "stbir_resize_uint8", stbcall.}

proc resize*(
  input: openarray[byte],
  in_w, in_h: int,
  out_w, out_h: int,
  channels: int,
  stride: int = 0
): seq[byte] =
  var outpx: seq[byte]
  newSeq(outpx, out_w * out_h * channels)
  if stbir_resize_uint8(
      input[0].unsafeAddr, in_w.cint, in_h.cint, stride,
      outpx[0].unsafeAddr, out_w.cint, out_h.cint, stride,
      channels
  ) == 0:
    raise newException(STBIException, "Resize unsuccessful")
  return outpx
