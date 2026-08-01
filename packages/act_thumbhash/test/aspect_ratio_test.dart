import 'dart:convert';
import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:act_thumbhash/act_thumbhash.dart';

import 'helpers.dart';

/// Aspect ratios that exercise the luminance coefficient count, including the
/// extreme ones where `lx`/`ly` fall below the 3-coefficient floor the decoder
/// applies. Each is tested in both orientations.
const _sizes = [
  (64, 64), // 1:1
  (100, 75), // 4:3
  (100, 56), // 16:9
  (100, 50), // 2:1
  (100, 40), // 2.5:1
  (100, 30), // 3.3:1
  (100, 20), // 5:1
  (100, 10), // 10:1
  (100, 4), // 25:1
  (128, 1), // 128:1
];

void main() {
  group('aspect ratio roundtrip', () {
    for (final (long, short) in _sizes) {
      for (final landscape in [true, false]) {
        for (final alpha in [false, true]) {
          final w = landscape ? long : short;
          final h = landscape ? short : long;
          final label = '${w}x$h ${alpha ? 'with alpha' : 'opaque'}';

          // Shared by both tests below; encoding at declaration time also
          // means an encoder throw fails the suite loudly at load.
          final hash = ThumbHash.encodeSync(
            w,
            h,
            solid(w, h, r: 200, g: 120, b: 40, a: alpha ? 128 : 255),
          );

          test('encodes and decodes $label', () {
            // Regression: this used to throw RangeError once the aspect
            // ratio pushed lx or ly below 3.
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
            // Decoding a hash truncated by one byte must fail, proving the
            // encoder does not over-allocate and hide a short write.
            expect(
              () => ThumbHash.decodeSync(hash.sublist(0, hash.length - 1)),
              throwsA(isA<Error>()),
              reason: 'hash appears to be larger than the decoder needs',
            );
          });
        }
      }
    }
  });

  test('async path agrees with sync path across aspect ratios', () async {
    for (final (w, h) in _sizes) {
      final rgba = solid(w, h, r: 90, g: 160, b: 210);
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

    // Pin sampled pixel values. This test runs on the VM and in the browser,
    // so it anchors the decoder's arithmetic across compilers — dimensional
    // checks alone stay green when a platform-specific numeric bug garbles
    // pixel data. The +-2 tolerance absorbs last-ulp trigonometry differences
    // between platforms; real decode regressions deviate by far more.
    const samples = {
      0: (77, 80, 98, 255),
      100: (104, 101, 110, 255),
      300: (112, 101, 103, 255),
      367: (95, 87, 88, 255),
      500: (60, 54, 57, 255),
      735: (34, 43, 61, 255),
    };
    for (final MapEntry(key: offset, value: (r, g, b, a)) in samples.entries) {
      final i = offset * 4;
      expect(result.rgba[i], closeTo(r, 2), reason: 'r at pixel $offset');
      expect(result.rgba[i + 1], closeTo(g, 2), reason: 'g at pixel $offset');
      expect(result.rgba[i + 2], closeTo(b, 2), reason: 'b at pixel $offset');
      expect(result.rgba[i + 3], a, reason: 'a at pixel $offset');
    }
  });
}
