import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:act_thumbhash/act_thumbhash.dart';

/// Builds a solid-colour RGBA buffer.
Uint8List solid(int w, int h, int r, int g, int b, [int a = 255]) {
  final bytes = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    bytes[i * 4] = r;
    bytes[i * 4 + 1] = g;
    bytes[i * 4 + 2] = b;
    bytes[i * 4 + 3] = a;
  }
  return bytes;
}

/// Aspect ratios that exercise the luminance coefficient count, including the
/// extreme ones where `lx`/`ly` fall below the 3-coefficient floor the decoder
/// applies. Each is tested in both orientations.
const _sizes = [
  [64, 64], // 1:1
  [100, 75], // 4:3
  [100, 56], // 16:9
  [100, 50], // 2:1
  [100, 40], // 2.5:1
  [100, 30], // 3.3:1
  [100, 20], // 5:1
  [100, 10], // 10:1
  [100, 4], // 25:1
  [128, 1], // 128:1
];

void main() {
  group('aspect ratio roundtrip', () {
    for (final size in _sizes) {
      for (final landscape in [true, false]) {
        for (final alpha in [false, true]) {
          final w = landscape ? size[0] : size[1];
          final h = landscape ? size[1] : size[0];
          final label = '${w}x$h ${alpha ? 'with alpha' : 'opaque'}';

          test('encodes and decodes $label', () {
            final rgba = solid(w, h, 200, 120, 40, alpha ? 128 : 255);

            // Regression: both of these used to throw RangeError once the
            // aspect ratio pushed lx or ly below 3.
            final hash = ThumbHash.encodeSync(w, h, rgba);
            final result = ThumbHash.decodeSync(hash);

            expect(result.width, greaterThan(0));
            expect(result.height, greaterThan(0));
            expect(result.rgba.length, result.width * result.height * 4);

            // A solid source image must decode back to roughly that colour.
            // This catches coefficient misalignment that does not overrun the
            // buffer but does shift every value that follows it.
            //
            // Skipped when the short side is only a pixel or two: the DCT
            // always uses at least 3 coefficients per axis, so a 1px-tall
            // image evaluates cos(pi/1 * 0.5 * 2) = -1 and a constant signal
            // picks up genuine nonzero coefficients. The reference
            // implementation behaves the same way, so this is the format, not
            // a defect.
            if (math.min(w, h) >= 4) {
              expect(result.rgba[0], closeTo(200, 20), reason: 'red');
              expect(result.rgba[1], closeTo(120, 20), reason: 'green');
              expect(result.rgba[2], closeTo(40, 20), reason: 'blue');
            }
          });

          test('hash length matches what the decoder consumes for $label', () {
            final rgba = solid(w, h, 200, 120, 40, alpha ? 128 : 255);
            final hash = ThumbHash.encodeSync(w, h, rgba);

            // Decoding a hash truncated by one byte must fail, proving the
            // encoder does not over-allocate and hide a short write.
            expect(
              () => ThumbHash.decodeSync(
                Uint8List.fromList(hash.sublist(0, hash.length - 1)),
              ),
              throwsA(isA<Error>()),
              reason: 'hash appears to be larger than the decoder needs',
            );
          });
        }
      }
    }
  });

  test('async path agrees with sync path across aspect ratios', () async {
    for (final size in _sizes) {
      final w = size[0], h = size[1];
      final rgba = solid(w, h, 90, 160, 210);
      expect(
        await ThumbHash.encodeAsync(w, h, rgba),
        equals(ThumbHash.encodeSync(w, h, rgba)),
        reason: '${w}x$h',
      );
    }
  });

  test('decodes the reference vector from the ThumbHash project', () {
    final bytes =
        base64.decode(base64.normalize('1QcSHQRnh493V4dIh4eXh1h4kJUI'));
    final result = ThumbHash.decodeSync(bytes);
    expect(result.width, 23);
    expect(result.height, 32);
    expect(result.rgba.length, 23 * 32 * 4);
  });
}
