import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:isolate';

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
  /// thread. Use this for UI applications.
  ///
  /// [rgba] must contain width * height * 4 bytes (RGBA format).
  /// RGB should NOT be premultiplied by A.
  ///
  /// Returns the ThumbHash as a [Uint8List].
  ///
  /// Throws [ArgumentError] if the size of [rgba] didn't match width * height * 4.
  static Future<Uint8List> encodeAsync(
    int width,
    int height,
    Uint8List rgba,
  ) async {
    return Isolate.run(() => encodeSync(width, height, rgba));
  }

  /// Decodes a ThumbHash to an RGBA image asynchronously.
  ///
  /// This runs the decoding in a separate isolate to avoid blocking the main
  /// thread. Use this for UI applications.
  ///
  /// [hash] is the ThumbHash bytes.
  ///
  /// Returns [ThumbHashDecodeResult] containing width, height, and RGBA data.
  /// RGB is NOT premultiplied by A.
  ///
  /// Throws [ArgumentError] if hash is too short.
  static Future<ThumbHashDecodeResult> decodeAsync(Uint8List hash) async {
    return Isolate.run(() => decodeSync(hash));
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
      final newW = (width * scale).toInt();
      final newH = (height * scale).toInt();
      
      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgba.buffer,
        numChannels: 4,
      );
      
      final resized = img.copyResize(
        image,
        width: newW,
        height: newH,
        interpolation: img.Interpolation.nearest,
      );
      
      width = newW;
      height = newH;
      rgba = resized.getBytes();
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
    final (lDc, lAc, lScale) = _encodeChannel(l, w, h, lx, ly);
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

    // Calculate hash size
    var hashSize = 4 + _countAcCoeffs(lx, ly);
    hashSize += _countAcCoeffs(3, 3);
    hashSize += _countAcCoeffs(3, 3);
    if (hasAlpha) {
      hashSize += 1 + _countAcCoeffs(5, 5);
    }
    hashSize = (hashSize + 1) ~/ 2 + 3;

    final hash = Uint8List(hashSize);

    // Pack header bytes
    hash[0] = lDcInt | (pDcInt << 6);
    hash[1] = (pDcInt >> 2) | (qDcInt << 4);
    hash[2] = (qDcInt >> 4) | (lScaleInt << 2) | (hasAlphaInt << 7);
    hash[3] = lCount | (pScaleInt << 3);
    hash[4] = (pScaleInt >> 5) | (qScaleInt << 1) | (isLandscapeInt << 7);

    var nibbleIndex = 10;
    if (hasAlpha) {
      final aDcInt = (15.0 * aDc).round().clamp(0, 15);
      final aScaleInt = (15.0 * aScale).round().clamp(0, 15);
      hash[5] = aDcInt | (aScaleInt << 4);
      nibbleIndex = 12;
    }

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
  static ThumbHashDecodeResult decodeSync(Uint8List hash) {
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
    const baseSize = 32;
    final w = (ratio > 1) ? baseSize : (baseSize * ratio).round();
    final h = (ratio > 1) ? (baseSize / ratio).round() : baseSize;

    final rgba = Uint8List(w * h * 4);

    final fxL = Float64List(lx);
    final fyL = Float64List(ly);
    final fxP = Float64List(3);
    final fyP = Float64List(3);
    final fxQ = Float64List(3);
    final fyQ = Float64List(3);
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
          fxP[cx] = math.cos(math.pi / w * (x + 0.5) * cx);
          fxQ[cx] = math.cos(math.pi / w * (x + 0.5) * cx);
        }
        for (var cy = 0; cy < 3; cy++) {
          fyP[cy] = math.cos(math.pi / h * (y + 0.5) * cy);
          fyQ[cy] = math.cos(math.pi / h * (y + 0.5) * cy);
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
              pVal += pAc[acIndex++] * fxP[cx] * fyP[cy];
            }
          }
        }

        var qVal = qDc;
        acIndex = 0;
        for (var cy = 0; cy < 3; cy++) {
          for (var cx = 0; cx < 3; cx++) {
            if ((cx != 0 || cy != 0) && (cx * 3 + cy * 3 < 9)) {
              qVal += qAc[acIndex++] * fxQ[cx] * fyQ[cy];
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
