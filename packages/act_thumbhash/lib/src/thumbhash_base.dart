import 'dart:math' as math;
import 'dart:typed_data';

// dart2wasm ships a dart:isolate stub, so selecting on `dart.library.isolate`
// would route wasm builds to Isolate.run, which throws at runtime there.
// `dart.library.js_interop` is true for both dart2js and dart2wasm, sending
// every web target to the event-loop fallback instead.
import 'isolates_io.dart' if (dart.library.js_interop) 'isolates_web.dart';

/// Result of decoding a ThumbHash, containing the RGBA image data.
class ThumbHashDecodeResult {
  /// Width of the decoded image in pixels.
  final int width;

  /// Height of the decoded image in pixels.
  final int height;

  /// RGBA pixel data as a flat array (4 bytes per pixel: R, G, B, A).
  /// Length is width * height * 4.
  final Uint8List rgba;

  const ThumbHashDecodeResult({
    required this.width,
    required this.height,
    required this.rgba,
  });
}

const maxEncodeDim = 128;

/// ThumbHash encoder and decoder.
///
/// Provides both synchronous and asynchronous methods for encoding and
/// decoding ThumbHash image placeholders.
class ThumbHash {
  ThumbHash._();

  // ============================================================
  // ASYNC METHODS (using isolates)
  // ============================================================

  /// Encodes an RGBA image to a ThumbHash asynchronously.
  ///
  /// This runs the encoding in a separate isolate to avoid blocking the main
  /// thread. Use this for UI applications. On platforms without isolates (the
  /// web), the encoding runs on the main thread after yielding once to the
  /// event loop.
  ///
  /// [rgba] must contain width * height * 4 bytes (RGBA format).
  /// RGB should NOT be premultiplied by A.
  /// Do not mutate [rgba] until the returned future completes: on the web the
  /// encoder reads the live buffer, whereas isolates receive a copy.
  ///
  /// Returns the ThumbHash as a [Uint8List].
  ///
  /// Throws [ArgumentError] if the size of [rgba] didn't match width * height * 4.
  static Future<Uint8List> encodeAsync(
    int width,
    int height,
    Uint8List rgba,
  ) async {
    return runIsolated(() => encodeSync(width, height, rgba));
  }

  /// Decodes a ThumbHash to an RGBA image asynchronously.
  ///
  /// This runs the decoding in a separate isolate to avoid blocking the main
  /// thread. Use this for UI applications. On platforms without isolates (the
  /// web), the decoding runs on the main thread after yielding once to the
  /// event loop.
  ///
  /// [hash] is the ThumbHash bytes. Do not mutate it until the returned
  /// future completes: on the web the decoder reads the live buffer, whereas
  /// isolates receive a copy.
  ///
  /// Returns [ThumbHashDecodeResult] containing width, height, and RGBA data.
  /// RGB is NOT premultiplied by A.
  ///
  /// Throws [ArgumentError] if hash is too short.
  static Future<ThumbHashDecodeResult> decodeAsync(Uint8List hash,
      {int baseSize = 32}) async {
    return runIsolated(() => decodeSync(hash, baseSize: baseSize));
  }

  // ============================================================
  // SYNC METHODS
  // ============================================================

  /// Encodes an RGBA image to a ThumbHash synchronously.
  ///
  /// [rgba] must contain width * height * 4 bytes (RGBA format).
  /// RGB should NOT be premultiplied by A.
  ///
  /// Returns the ThumbHash as a [Uint8List].
  ///
  /// Throws [ArgumentError] if the size of [rgba] didn't match width * height * 4.
  static Uint8List encodeSync(int width, int height, Uint8List rgba) {
    // Validate input
    if (rgba.length != width * height * 4) {
      throw ArgumentError(
        'Expected ${width * height * 4} bytes, got ${rgba.length}',
      );
    }

    // resize images larger than max encoding dimension
    // (no point in encoding large images)
    if (math.max(width, height) > maxEncodeDim) {
      final scale = maxEncodeDim / math.max(width, height);
      // The floor keeps extreme aspect ratios (beyond maxEncodeDim:1) from
      // scaling the short side down to zero pixels.
      final newW = math.max(1, (width * scale).toInt());
      final newH = math.max(1, (height * scale).toInt());

      final newRgba = Uint8List(newW * newH * 4);
      for (var y = 0; y < newH; y++) {
        for (var x = 0; x < newW; x++) {
          final srcX = (x * width / newW).floor();
          final srcY = (y * height / newH).floor();
          final srcIdx = (srcY * width + srcX) * 4;
          final dstIdx = (y * newW + x) * 4;
          newRgba[dstIdx] = rgba[srcIdx];
          newRgba[dstIdx + 1] = rgba[srcIdx + 1];
          newRgba[dstIdx + 2] = rgba[srcIdx + 2];
          newRgba[dstIdx + 3] = rgba[srcIdx + 3];
        }
      }

      width = newW;
      height = newH;
      rgba = newRgba;
    }

    final w = width;
    final h = height;

    // Determine the average color
    double avgR = 0, avgG = 0, avgB = 0, avgA = 0;
    for (var i = 0, j = 0; i < w * h; i++, j += 4) {
      final alpha = rgba[j + 3] / 255.0;
      avgR += alpha / 255.0 * rgba[j];
      avgG += alpha / 255.0 * rgba[j + 1];
      avgB += alpha / 255.0 * rgba[j + 2];
      avgA += alpha;
    }

    if (avgA > 0) {
      avgR /= avgA;
      avgG /= avgA;
      avgB /= avgA;
    }

    final hasAlpha = avgA < w * h;
    final lLimit = hasAlpha ? 5 : 7;
    final maxWH = math.max(w, h);
    final lx = math.max(1, (lLimit * w / maxWH).round());
    final ly = math.max(1, (lLimit * h / maxWH).round());

    // The raw lx/ly go into the header, but the luminance channel is always
    // encoded with at least 3 coefficients per axis. The decoder applies the
    // same floor when reading the header back, so skipping it here would emit
    // fewer AC coefficients than any decoder expects.
    final lxEnc = math.max(3, lx);
    final lyEnc = math.max(3, ly);

    // Prepare channel data
    final l = Float64List(w * h);
    final p = Float64List(w * h);
    final q = Float64List(w * h);
    final a = Float64List(w * h);

    // Convert to LPQ color space
    for (var i = 0, j = 0; i < w * h; i++, j += 4) {
      final alpha = rgba[j + 3] / 255.0;
      final r = avgR * (1 - alpha) + (rgba[j] / 255.0) * alpha;
      final g = avgG * (1 - alpha) + (rgba[j + 1] / 255.0) * alpha;
      final b = avgB * (1 - alpha) + (rgba[j + 2] / 255.0) * alpha;
      l[i] = (r + g + b) / 3;
      p[i] = (r + g) / 2 - b;
      q[i] = r - g;
      a[i] = alpha;
    }

    // Encode using DCT
    final (lDc, lAc, lScale) = _encodeChannel(l, w, h, lxEnc, lyEnc);
    final (pDc, pAc, pScale) = _encodeChannel(p, w, h, 3, 3);
    final (qDc, qAc, qScale) = _encodeChannel(q, w, h, 3, 3);

    double aDc = 1.0;
    List<double> aAc = [];
    double aScale = 1.0;

    if (hasAlpha) {
      final result = _encodeChannel(a, w, h, 5, 5);
      aDc = result.$1;
      aAc = result.$2;
      aScale = result.$3;
    }

    final isLandscape = w > h;

    // Calculate header values
    final lDcInt = (63.0 * lDc).round().clamp(0, 63);
    final pDcInt = (31.5 + 31.5 * pDc).round().clamp(0, 63);
    final qDcInt = (31.5 + 31.5 * qDc).round().clamp(0, 63);
    final lScaleInt = (31.0 * lScale).round().clamp(0, 31);
    final hasAlphaInt = hasAlpha ? 1 : 0;

    final lCount = isLandscape ? ly : lx;
    final pScaleInt = (63.0 * pScale).round().clamp(0, 63);
    final qScaleInt = (63.0 * qScale).round().clamp(0, 63);
    final isLandscapeInt = isLandscape ? 1 : 0;

    // Calculate hash size. The header is 5 bytes, followed by one more byte
    // holding the alpha DC and scale when the image has alpha, so AC
    // coefficients start at nibble 10 (12 with alpha) and take one nibble each.
    final acStartNibble = hasAlpha ? 12 : 10;
    var acCount = _countAcCoeffs(lxEnc, lyEnc);
    acCount += _countAcCoeffs(3, 3) * 2;
    if (hasAlpha) {
      acCount += _countAcCoeffs(5, 5);
    }
    final hashSize = (acStartNibble + acCount + 1) ~/ 2;

    final hash = Uint8List(hashSize);

    // Pack header bytes
    hash[0] = lDcInt | (pDcInt << 6);
    hash[1] = (pDcInt >> 2) | (qDcInt << 4);
    hash[2] = (qDcInt >> 4) | (lScaleInt << 2) | (hasAlphaInt << 7);
    hash[3] = lCount | (pScaleInt << 3);
    hash[4] = (pScaleInt >> 5) | (qScaleInt << 1) | (isLandscapeInt << 7);

    if (hasAlpha) {
      final aDcInt = (15.0 * aDc).round().clamp(0, 15);
      final aScaleInt = (15.0 * aScale).round().clamp(0, 15);
      hash[5] = aDcInt | (aScaleInt << 4);
    }

    var nibbleIndex = acStartNibble;

    void writeNibble(int value) {
      final byteIndex = nibbleIndex ~/ 2;
      if (nibbleIndex % 2 == 0) {
        hash[byteIndex] = value;
      } else {
        hash[byteIndex] |= value << 4;
      }
      nibbleIndex++;
    }

    for (final ac in lAc) {
      writeNibble((15.0 * ac).round().clamp(0, 15));
    }
    for (final ac in pAc) {
      writeNibble((15.0 * ac).round().clamp(0, 15));
    }
    for (final ac in qAc) {
      writeNibble((15.0 * ac).round().clamp(0, 15));
    }
    if (hasAlpha) {
      for (final ac in aAc) {
        writeNibble((15.0 * ac).round().clamp(0, 15));
      }
    }

    return hash;
  }

  /// Decodes a ThumbHash to an RGBA image synchronously.
  ///
  /// [hash] is the ThumbHash bytes.
  ///
  /// Returns [ThumbHashDecodeResult] containing width, height, and RGBA data.
  /// RGB is NOT premultiplied by A.
  ///
  /// Throws [ArgumentError] if [hash] is shorter than its own header says it
  /// should be, for example because it was truncated in transport, or if
  /// [baseSize] is smaller than 1.
  static ThumbHashDecodeResult decodeSync(Uint8List hash, {int baseSize = 32}) {
    if (baseSize < 1) {
      throw ArgumentError.value(baseSize, 'baseSize', 'must be at least 1');
    }
    if (hash.length < 5) {
      throw ArgumentError('Hash is too short (minimum 5 bytes)');
    }

    // Read header
    final header1 =
        hash[0] | (hash[1] << 8) | (hash[2] << 16) | (hash[3] << 24);
    final header2 = hash[4];

    final lDc = (header1 & 63) / 63.0;
    final pDc = ((header1 >> 6) & 63) / 31.5 - 1.0;
    final qDc = ((header1 >> 12) & 63) / 31.5 - 1.0;
    final lScale = ((header1 >> 18) & 31) / 31.0;
    final hasAlpha = ((header1 >> 23) & 1) != 0;
    final lCount = (header1 >> 24) & 7;
    final pScale = (((header1 >> 27) & 31) | ((header2 & 1) << 5)) / 63.0;
    final qScale = ((header2 >> 1) & 63) / 63.0;
    final isLandscape = ((header2 >> 7) & 1) != 0;

    int lx, ly;
    if (isLandscape) {
      lx = math.max(3, hasAlpha ? 5 : 7);
      ly = math.max(3, lCount);
    } else {
      lx = math.max(3, lCount);
      ly = math.max(3, hasAlpha ? 5 : 7);
    }

    double aDc = 1.0;
    double aScale = 1.0;

    int acStart;
    if (hasAlpha) {
      if (hash.length < 6) {
        throw ArgumentError('Hash is too short for alpha channel');
      }
      aDc = (hash[5] & 15) / 15.0;
      aScale = ((hash[5] >> 4) & 15) / 15.0;
      acStart = 12;
    } else {
      acStart = 10;
    }

    // The header determines exactly how many AC coefficient nibbles follow.
    // Validate up front so a truncated hash fails with a clear error instead
    // of an out-of-bounds read partway through decoding.
    var acCount = _countAcCoeffs(lx, ly) + 2 * _countAcCoeffs(3, 3);
    if (hasAlpha) {
      acCount += _countAcCoeffs(5, 5);
    }
    final expectedLength = (acStart + acCount + 1) ~/ 2;
    if (hash.length < expectedLength) {
      throw ArgumentError(
        'Hash is truncated: its header requires $expectedLength bytes, '
        'got ${hash.length}',
      );
    }

    var nibbleIndex = acStart;

    int readNibble() {
      final byteIndex = nibbleIndex ~/ 2;
      final value = (nibbleIndex % 2 == 0)
          ? (hash[byteIndex] & 15)
          : ((hash[byteIndex] >> 4) & 15);
      nibbleIndex++;
      return value;
    }

    final lAc = <double>[];
    final pAc = <double>[];
    final qAc = <double>[];
    final aAc = <double>[];

    for (var y = 0; y < ly; y++) {
      for (var x = 0; x < lx; x++) {
        if ((x != 0 || y != 0) && (x * ly + y * lx < lx * ly)) {
          lAc.add((readNibble() / 7.5 - 1.0) * lScale);
        }
      }
    }

    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 3; x++) {
        if ((x != 0 || y != 0) && (x * 3 + y * 3 < 9)) {
          pAc.add((readNibble() / 7.5 - 1.0) * pScale);
        }
      }
    }

    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 3; x++) {
        if ((x != 0 || y != 0) && (x * 3 + y * 3 < 9)) {
          qAc.add((readNibble() / 7.5 - 1.0) * qScale);
        }
      }
    }

    if (hasAlpha) {
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          if ((x != 0 || y != 0) && (x * 5 + y * 5 < 25)) {
            aAc.add((readNibble() / 7.5 - 1.0) * aScale);
          }
        }
      }
    }

    // Decode image
    final ratio = _thumbHashToApproximateAspectRatioInternal(
      lx,
      ly,
      isLandscape,
    );
    // The floor keeps small baseSize values (e.g. 1) from rounding the short
    // side down to zero pixels.
    final shortSide = math.max(1, (baseSize / ratio).round());
    final w = isLandscape ? baseSize : shortSide;
    final h = isLandscape ? shortSide : baseSize;

    final rgba = Uint8List(w * h * 4);

    final fxL = Float64List(lx);
    final fyL = Float64List(ly);
    // The P and Q channels share the same 3x3 basis functions.
    final fxPQ = Float64List(3);
    final fyPQ = Float64List(3);
    final fxA = hasAlpha ? Float64List(5) : Float64List(0);
    final fyA = hasAlpha ? Float64List(5) : Float64List(0);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        for (var cx = 0; cx < lx; cx++) {
          fxL[cx] = math.cos(math.pi / w * (x + 0.5) * cx);
        }
        for (var cy = 0; cy < ly; cy++) {
          fyL[cy] = math.cos(math.pi / h * (y + 0.5) * cy);
        }
        for (var cx = 0; cx < 3; cx++) {
          fxPQ[cx] = math.cos(math.pi / w * (x + 0.5) * cx);
        }
        for (var cy = 0; cy < 3; cy++) {
          fyPQ[cy] = math.cos(math.pi / h * (y + 0.5) * cy);
        }
        if (hasAlpha) {
          for (var cx = 0; cx < 5; cx++) {
            fxA[cx] = math.cos(math.pi / w * (x + 0.5) * cx);
          }
          for (var cy = 0; cy < 5; cy++) {
            fyA[cy] = math.cos(math.pi / h * (y + 0.5) * cy);
          }
        }

        var l = lDc;
        var acIndex = 0;
        for (var cy = 0; cy < ly; cy++) {
          for (var cx = 0; cx < lx; cx++) {
            if ((cx != 0 || cy != 0) && (cx * ly + cy * lx < lx * ly)) {
              l += lAc[acIndex++] * fxL[cx] * fyL[cy];
            }
          }
        }

        var pVal = pDc;
        acIndex = 0;
        for (var cy = 0; cy < 3; cy++) {
          for (var cx = 0; cx < 3; cx++) {
            if ((cx != 0 || cy != 0) && (cx * 3 + cy * 3 < 9)) {
              pVal += pAc[acIndex++] * fxPQ[cx] * fyPQ[cy];
            }
          }
        }

        var qVal = qDc;
        acIndex = 0;
        for (var cy = 0; cy < 3; cy++) {
          for (var cx = 0; cx < 3; cx++) {
            if ((cx != 0 || cy != 0) && (cx * 3 + cy * 3 < 9)) {
              qVal += qAc[acIndex++] * fxPQ[cx] * fyPQ[cy];
            }
          }
        }

        var aVal = aDc;
        if (hasAlpha) {
          acIndex = 0;
          for (var cy = 0; cy < 5; cy++) {
            for (var cx = 0; cx < 5; cx++) {
              if ((cx != 0 || cy != 0) && (cx * 5 + cy * 5 < 25)) {
                aVal += aAc[acIndex++] * fxA[cx] * fyA[cy];
              }
            }
          }
        }

        final b = l - 2.0 / 3.0 * pVal;
        final r = (3.0 * l - b + qVal) / 2.0;
        final g = r - qVal;

        final pixelIndex = (y * w + x) * 4;
        rgba[pixelIndex] = (r.clamp(0.0, 1.0) * 255).round();
        rgba[pixelIndex + 1] = (g.clamp(0.0, 1.0) * 255).round();
        rgba[pixelIndex + 2] = (b.clamp(0.0, 1.0) * 255).round();
        rgba[pixelIndex + 3] = (aVal.clamp(0.0, 1.0) * 255).round();
      }
    }

    return ThumbHashDecodeResult(width: w, height: h, rgba: rgba);
  }

  // ============================================================
  // PRIVATE HELPERS
  // ============================================================

  static int _countAcCoeffs(int nx, int ny) {
    var count = 0;
    for (var y = 0; y < ny; y++) {
      for (var x = 0; x < nx; x++) {
        if ((x != 0 || y != 0) && (x * ny + y * nx < nx * ny)) {
          count++;
        }
      }
    }
    return count;
  }

  static double _thumbHashToApproximateAspectRatioInternal(
    int lx,
    int ly,
    bool isLandscape,
  ) {
    return isLandscape
        ? lx.toDouble() / ly.toDouble()
        : ly.toDouble() / lx.toDouble();
  }

  static (double dc, List<double> ac, double scale) _encodeChannel(
    Float64List channel,
    int w,
    int h,
    int nx,
    int ny,
  ) {
    double dc = 0;
    final ac = <double>[];
    double scale = 0;

    for (var cy = 0; cy < ny; cy++) {
      for (var cx = 0; cx < nx; cx++) {
        var f = 0.0;
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            f += channel[y * w + x] *
                math.cos(math.pi / w * (x + 0.5) * cx) *
                math.cos(math.pi / h * (y + 0.5) * cy);
          }
        }
        f /= w * h;

        if (cx == 0 && cy == 0) {
          dc = f;
        } else if ((cx * ny + cy * nx < nx * ny)) {
          ac.add(f);
          if (f.abs() > scale) {
            scale = f.abs();
          }
        }
      }
    }

    if (scale > 0) {
      for (var i = 0; i < ac.length; i++) {
        ac[i] = 0.5 + 0.5 * ac[i] / scale;
      }
    }

    return (dc, ac, scale);
  }
}
