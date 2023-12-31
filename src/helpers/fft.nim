# https://raw.githubusercontent.com/ringabout/scim/master/src/scim/fft.nim

import math, complex, sugar, arraymancer, sequtils

type
  ComplexType = Complex[float] | Complex[float32]

proc bitReverseCopy[T: ComplexType](x: var seq[T]) =
  let n = x.len
  var
    k: int
    j: int = 0
  for i in 0 ..< n - 1:
    if i < j:
      swap(x[i], x[j])
    k = n shr 1
    while j >= k:
      j -= k
      k = k shr 1
    j += k

proc fftAid[T: ComplexType](x: seq[T], flag: float = -1.0): Tensor[T] {.noinit.} =
  let
    n = x.len
    n1 = nextPowerOfTwo(n)
    n2 = int(log2(n.float32))
    paddingLength = n1 - n
  var temp = x

  for i in 1 .. padding_length:
    temp.add(complex(0.0))
  bitReverseCopy[T](temp)
  for s in 1 .. n2:
    let
      m = 2 ^ s
      # flag * 2 * Pi
      wm = exp(complex(0.0, flag * 2.0 * Pi / float(m)))

    for k in countup(0, n1 - 1, m):
      var w = complex(1.0)
      let m2 = m shr 1
      for j in 0 ..< m2:
        let
          t = w * temp[k + j + m2]
          u = temp[k + j]
        temp[k + j] = u + t
        temp[k + j + m2] = u - t
        w = w * wm
  temp.toTensor.reshape(1, temp.len)

# proc fft*[T: ComplexType](x: Tensor[T]): Tensor[Complex[float]] {.noinit.}=
#   result = x.fftAid(-1)

proc fft*[T: ComplexType](x: seq[T] | Tensor[T]): Tensor[Complex[float]] {.noinit.}=
  var temp: seq[T]
  when x is seq:
    temp = x
  elif x is Tensor:
    temp = x.toRawSeq
  result = temp.fftAid(-1)

proc fft*[T: SomeFloat](x: seq[T] | Tensor[T]): Tensor[Complex[float]] {.noinit.}=
  result = fft(x.map(t=>t.complex))

proc ifft*[T: ComplexType](x: seq[T] | Tensor[T]): Tensor[Complex[float]] {.noinit.}=
  var temp: seq[T]
  when x is seq:
    temp = x
  elif x is Tensor:
    temp = x.toRawSeq
  # when T is SomeFloat:
  #   temp = temp.map(x=>complex(x))
  result = temp.fftAid(1).map(item => item / temp.len.float)

proc ifft*[T: SomeFloat](x: seq[T] | Tensor[T]): Tensor[Complex[float]] {.noinit.}=
  result = ifft(x.map(t=>t.complex))

proc rfft*[T: SomeFloat](input: Tensor[T]): Tensor[Complex[float]] {.noinit.} =
  assert input.rank == 2
  var
    n = input.shape[1]
    half = n shr 1
    A = newTensor[Complex[T]](half)
    B = newTensor[Complex[T]](half)
    # IA = newTensor[Complex[T]](half)
    # IB = newTensor[Complex[T]](half)
    X = newTensor[Complex[T]](1, half)
  result = newTensor[Complex[T]](1, n)
  for k in 0 ..< half:
    let
      coeff = 2.0 * float(k) * PI / float(n)
      cosPart = 0.5 * cos(coeff)
      sinPart = 0.5 * sin(coeff)
    A[k] = complex(0.5 - sinPart, -cosPart)
    B[k] = complex(0.5 + sinPart, cosPart)
    # IA[k] = conjugate(A[k])
    # IB[k] = conjugate(B[k])
  for i in 0 ..< half:
    X[0, i] = complex(input[0, 2 * i], input[0, 2 * i + 1])
  var temp = newTensor[Complex[T]](1, half + 1)
  # TODO not 2 ^ n
  temp[0, 0 ..< half] = X.fft
  temp[0, half] = temp[0, 0]
  result[0, 0] = temp[0, 0] * A[0] + conjugate(temp[0, half]) * B[0]
  for j in 1 ..< half:
    result[0, j] = temp[0, j] * A[j] + conjugate(temp[0, half - j]) * B[j]
    result[0, n-j] = conjugate(result[0, j])
  result[0, half] = complex(temp[0, 0].re - temp[0, 0].im, 0.0)

proc dct*[T: SomeFloat](input: Tensor[T]): Tensor[float] {.noinit.} =
  assert input.rank == 2
  let
    rows = input.shape[0]
    cols = input.shape[1]
    ## assert rows == 1
    n = input.size
    half = (n - 1) div 2
  var v = newTensor[T](rows, cols)
  v[0, 0 .. half] = input[0, _.._|2]
  if (n - 1) mod 2 == 1:
    v[0, half+1 .. _] = input[0, ^1..0|-2]
  else:
    v[0, half+1 .. _] = input[0, ^2..0|-2]
  var res = v.rfft
  for i in 0 ..< res.size:
    res[0, i] *= complex(2.0) * exp(complex(0.0, -Pi * float(i) / (2.0 * float(n))))
  return res.map(x=>x.re)

proc naiveDct*[T: SomeFloat](input: Tensor[T]): Tensor[float] {.noinit.}=
  assert input.rank == 2
  let
    _ = input.shape[0]
    cols = input.shape[1]
    factor = Pi / float(cols)
  result = newTensor[float](1, cols)
  for i in 0 ..< cols:
    var s: T
    for j in 0 ..< cols:
      s += input[0, j] * cos((T(j) + 0.5) * T(i) * factor)
    result[0, i] = 2 * s
