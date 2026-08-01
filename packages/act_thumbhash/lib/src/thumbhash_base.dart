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

/// Images whose longer side exceeds this are downscaled before encoding;
/// a ThumbHash cannot represent finer detail anyway.
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
  static Future<Uint8List> encodeAsync(int width, int height, Uint8List rgba) =>
      runIsolated(() => encodeSync(width, height, rgba));

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
  static Future<ThumbHashDecodeResult> decodeAsync(
    Uint8List hash, {
    int baseSize = 32,
  }) => runIsolated(() => decodeSync(hash, baseSize: baseSize));

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
        final srcRow = (y * height / newH).floor() * width;
        final dstRow = y * newW;
        for (var x = 0; x < newW; x++) {
          final srcIdx = (srcRow + (x * width / newW).floor()) * 4;
          final dstIdx = (dstRow + x) * 4;
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
    final n = w * h;

    // Determine the average color
    double avgR = 0, avgG = 0, avgB = 0, avgA = 0;
    for (var i = 0, j = 0; i < n; i++, j += 4) {
      final alpha = rgba[j + 3] / 255.0;
      final weight = alpha / 255.0;
      avgR += weight * rgba[j];
      avgG += weight * rgba[j + 1];
      avgB += weight * rgba[j + 2];
      avgA += alpha;
    }

    if (avgA > 0) {
      avgR /= avgA;
      avgG /= avgA;
      avgB /= avgA;
    }

    final hasAlpha = avgA < n;
    final lLimit = _lLimit(hasAlpha);
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
    final l = Float64List(n);
    final p = Float64List(n);
    final q = Float64List(n);
    final a = Float64List(n);

    // Convert to LPQ color space
    for (var i = 0, j = 0; i < n; i++, j += 4) {
      final alpha = rgba[j + 3] / 255.0;
      final invAlpha = 1 - alpha;
      final r = avgR * invAlpha + (rgba[j] / 255.0) * alpha;
      final g = avgG * invAlpha + (rgba[j + 1] / 255.0) * alpha;
      final b = avgB * invAlpha + (rgba[j + 2] / 255.0) * alpha;
      l[i] = (r + g + b) / 3;
      p[i] = (r + g) / 2 - b;
      q[i] = r - g;
      a[i] = alpha;
    }

    // Encode using DCT
    final (lDc, lAc, lScale) = _encodeChannel(l, w, h, lxEnc, lyEnc);
    final (pDc, pAc, pScale) = _encodeChannel(p, w, h, 3, 3);
    final (qDc, qAc, qScale) = _encodeChannel(q, w, h, 3, 3);

    var aDc = 1.0;
    var aAc = Float64List(0);
    var aScale = 1.0;
    if (hasAlpha) {
      (aDc, aAc, aScale) = _encodeChannel(a, w, h, 5, 5);
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

    final (acStartNibble, hashSize) = _hashLayout(lxEnc, lyEnc, hasAlpha);
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

    void writeAc(double value) {
      final quantized = (15.0 * value).round().clamp(0, 15);
      final byteIndex = nibbleIndex ~/ 2;
      if (nibbleIndex % 2 == 0) {
        hash[byteIndex] = quantized;
      } else {
        hash[byteIndex] |= quantized << 4;
      }
      nibbleIndex++;
    }

    for (final channelAcs in [lAc, pAc, qAc, if (hasAlpha) aAc]) {
      channelAcs.forEach(writeAc);
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
      lx = _lLimit(hasAlpha);
      ly = math.max(3, lCount);
    } else {
      lx = math.max(3, lCount);
      ly = _lLimit(hasAlpha);
    }

    var aDc = 1.0;
    var aScale = 1.0;
    if (hasAlpha) {
      if (hash.length < 6) {
        throw ArgumentError('Hash is too short for alpha channel');
      }
      aDc = (hash[5] & 15) / 15.0;
      aScale = ((hash[5] >> 4) & 15) / 15.0;
    }

    // The header determines exactly how many AC coefficient nibbles follow.
    // Validate up front so a truncated hash fails with a clear error instead
    // of an out-of-bounds read partway through decoding.
    final (acStartNibble, expectedLength) = _hashLayout(lx, ly, hasAlpha);
    if (hash.length < expectedLength) {
      throw ArgumentError(
        'Hash is truncated: its header requires $expectedLength bytes, '
        'got ${hash.length}',
      );
    }

    var nibbleIndex = acStartNibble;

    int readNibble() {
      final byteIndex = nibbleIndex ~/ 2;
      final value = (nibbleIndex % 2 == 0)
          ? (hash[byteIndex] & 15)
          : ((hash[byteIndex] >> 4) & 15);
      nibbleIndex++;
      return value;
    }

    Float64List readAcs(int nx, int ny, double scale) {
      final ac = Float64List(_countAcCoeffs(nx, ny));
      var i = 0;
      _forEachAc(nx, ny, (_, _) {
        ac[i++] = (readNibble() / 7.5 - 1.0) * scale;
      });
      return ac;
    }

    final lAc = readAcs(lx, ly, lScale);
    final pAc = readAcs(3, 3, pScale);
    final qAc = readAcs(3, 3, qScale);
    final aAc = hasAlpha ? readAcs(5, 5, aScale) : Float64List(0);

    // Decode image
    final ratio = isLandscape ? lx / ly : ly / lx;
    // The floor keeps small baseSize values (e.g. 1) from rounding the short
    // side down to zero pixels.
    final shortSide = math.max(1, (baseSize / ratio).round());
    final w = isLandscape ? baseSize : shortSide;
    final h = isLandscape ? shortSide : baseSize;

    final rgba = Uint8List(w * h * 4);

    // Precompute the DCT basis tables; the values depend only on the pixel
    // position and coefficient index, and all channels share the expression.
    final maxCx = math.max(lx, hasAlpha ? 5 : 3);
    final maxCy = math.max(ly, hasAlpha ? 5 : 3);
    final fx = Float64List(w * maxCx);
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < maxCx; c++) {
        fx[x * maxCx + c] = math.cos(math.pi / w * (x + 0.5) * c);
      }
    }
    final fy = Float64List(h * maxCy);
    for (var y = 0; y < h; y++) {
      for (var c = 0; c < maxCy; c++) {
        fy[y * maxCy + c] = math.cos(math.pi / h * (y + 0.5) * c);
      }
    }

    // The coefficient walk order is fixed per decode, so resolve it once
    // instead of re-evaluating the traversal condition for every pixel.
    final lCoeffs = _acCoeffs(lx, ly);
    final pqCoeffs = _acCoeffs(3, 3);
    final aCoeffs = hasAlpha ? _acCoeffs(5, 5) : const <(int, int)>[];

    double sample(
      double dc,
      Float64List ac,
      List<(int, int)> coeffs,
      int fxBase,
      int fyBase,
    ) {
      var value = dc;
      for (var i = 0; i < coeffs.length; i++) {
        final (cx, cy) = coeffs[i];
        value += ac[i] * fx[fxBase + cx] * fy[fyBase + cy];
      }
      return value;
    }

    for (var y = 0; y < h; y++) {
      final fyBase = y * maxCy;
      for (var x = 0; x < w; x++) {
        final fxBase = x * maxCx;

        final l = sample(lDc, lAc, lCoeffs, fxBase, fyBase);
        final pVal = sample(pDc, pAc, pqCoeffs, fxBase, fyBase);
        final qVal = sample(qDc, qAc, pqCoeffs, fxBase, fyBase);
        final aVal = hasAlpha ? sample(aDc, aAc, aCoeffs, fxBase, fyBase) : aDc;

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

  /// Number of luminance coefficients along the longer axis.
  static int _lLimit(bool hasAlpha) => hasAlpha ? 5 : 7;

  /// Visits every stored AC coefficient of an nx x ny channel in stream
  /// order: row by row, skipping the DC term and the upper coefficient
  /// triangle. This single traversal defines the format's coefficient
  /// layout; the encoder, the decoder, and the size accounting all use it.
  static void _forEachAc(int nx, int ny, void Function(int cx, int cy) visit) {
    for (var cy = 0; cy < ny; cy++) {
      for (var cx = 0; cx < nx; cx++) {
        if ((cx != 0 || cy != 0) && (cx * ny + cy * nx < nx * ny)) {
          visit(cx, cy);
        }
      }
    }
  }

  static int _countAcCoeffs(int nx, int ny) {
    var count = 0;
    _forEachAc(nx, ny, (_, _) => count++);
    return count;
  }

  static List<(int, int)> _acCoeffs(int nx, int ny) {
    final coeffs = <(int, int)>[];
    _forEachAc(nx, ny, (cx, cy) => coeffs.add((cx, cy)));
    return coeffs;
  }

  /// The nibble where AC coefficients start and the total byte length of a
  /// hash with the given luminance dimensions. Shared by the encoder's
  /// allocation and the decoder's truncation validation so the two cannot
  /// drift apart.
  static (int acStartNibble, int byteLength) _hashLayout(
    int lx,
    int ly,
    bool hasAlpha,
  ) {
    // The header is 5 bytes, followed by one more byte holding the alpha DC
    // and scale when the image has alpha, so AC coefficients start at nibble
    // 10 (12 with alpha) and take one nibble each.
    final acStartNibble = hasAlpha ? 12 : 10;
    var acCount = _countAcCoeffs(lx, ly) + 2 * _countAcCoeffs(3, 3);
    if (hasAlpha) {
      acCount += _countAcCoeffs(5, 5);
    }
    return (acStartNibble, (acStartNibble + acCount + 1) ~/ 2);
  }

  static (double dc, Float64List ac, double scale) _encodeChannel(
    Float64List channel,
    int w,
    int h,
    int nx,
    int ny,
  ) {
    // Precompute the DCT basis tables; the cosines depend only on
    // (position, coefficient index), not on the coefficient pair being
    // accumulated, so computing them per pixel would redo identical work
    // w * h times.
    final cosX = Float64List(nx * w);
    for (var cx = 0; cx < nx; cx++) {
      for (var x = 0; x < w; x++) {
        cosX[cx * w + x] = math.cos(math.pi / w * (x + 0.5) * cx);
      }
    }
    final cosY = Float64List(ny * h);
    for (var cy = 0; cy < ny; cy++) {
      for (var y = 0; y < h; y++) {
        cosY[cy * h + y] = math.cos(math.pi / h * (y + 0.5) * cy);
      }
    }

    double coefficient(int cx, int cy) {
      var f = 0.0;
      final xBase = cx * w;
      final yBase = cy * h;
      for (var y = 0; y < h; y++) {
        final row = y * w;
        final basisY = cosY[yBase + y];
        for (var x = 0; x < w; x++) {
          f += channel[row + x] * cosX[xBase + x] * basisY;
        }
      }
      return f / (w * h);
    }

    final dc = coefficient(0, 0);
    final ac = Float64List(_countAcCoeffs(nx, ny));
    var scale = 0.0;
    var i = 0;
    _forEachAc(nx, ny, (cx, cy) {
      final f = coefficient(cx, cy);
      ac[i++] = f;
      if (f.abs() > scale) {
        scale = f.abs();
      }
    });

    if (scale > 0) {
      for (var j = 0; j < ac.length; j++) {
        ac[j] = 0.5 + 0.5 * ac[j] / scale;
      }
    }

    return (dc, ac, scale);
  }
}
