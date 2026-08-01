## Unreleased

- The minimum supported SDK is now Dart 3.8.

## 1.0.0

- **Perf**: the encoder and decoder now precompute their DCT basis tables and
  skip coefficients the format discards, making encoding roughly 9x and
  decoding roughly 4x faster. Output is byte-for-byte unchanged.
- **Fix**: `decodeSync` now validates the hash length against what its header
  requires and throws the documented `ArgumentError` for truncated input,
  instead of surfacing an out-of-bounds `RangeError` partway through decoding.
- **Fix**: `decodeSync` and `decodeAsync` now reject `baseSize` values below 1
  with an `ArgumentError`, and small `baseSize` values can no longer round the
  decoded image's short side down to zero pixels.
- **Fix**: encoding images with an aspect ratio steeper than 128:1 no longer
  throws; the internal downscale now keeps the short side at a minimum of one
  pixel.
- **Feat**: Web support. `dart:isolate` is no longer imported unconditionally;
  on the web (both dart2js and dart2wasm) `encodeAsync` and `decodeAsync` run
  the computation on the event loop after yielding once, since isolates are
  unavailable there. Native behaviour is unchanged.
- **Fix**: `encodeSync` emitted too few luminance coefficients for images with
  an aspect ratio steeper than roughly 2.8:1 (2:1 with alpha), in either
  orientation. The resulting hashes were shorter than any decoder expects, so
  decoding them threw a `RangeError`, and they were not readable by other
  ThumbHash implementations. The luminance channel is now always encoded with
  at least 3 coefficients per axis, matching the reference implementation.
- **Fix**: the hash buffer was one byte too small for images with alpha whose
  coefficient count is odd (for example 100x75), making `encodeSync` throw a
  `RangeError` while writing its own output.

Hashes for images that encoded correctly before are unchanged.

## 1.0.0-dev.2

- Documentation and packaging updates

## 1.0.0-dev.1

- Initial pre-release
- Encode RGBA images to ThumbHash
- Decode ThumbHash to RGBA images
- Async methods using isolates
- Automatic downscaling for images larger than 128px
