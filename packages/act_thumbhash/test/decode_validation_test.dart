import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:act_thumbhash/act_thumbhash.dart';

import 'helpers.dart';

/// Matches the deliberate validation errors thrown by `decodeSync`, and
/// nothing else. A plain `throwsArgumentError` would be tautological here:
/// `RangeError` extends `ArgumentError`, so it also matches the accidental
/// out-of-bounds reads these tests exist to rule out.
final throwsValidationError = throwsA(
  isA<ArgumentError>()
      .having((e) => e is RangeError, 'is a RangeError', isFalse)
      .having(
        (e) => '${e.message}',
        'message',
        anyOf(contains('truncated'), contains('too short')),
      ),
);

void main() {
  group('extreme aspect ratios', () {
    // Regression: past maxEncodeDim:1 the downscale used to truncate the
    // short side to zero pixels, making the DCT produce NaN and encodeSync
    // throw an UnsupportedError.
    for (final dims in [
      [5000, 30],
      [30, 5000],
      [20000, 1],
      [1, 20000],
    ]) {
      final w = dims[0], h = dims[1];
      test('${w}x$h encodes and decodes', () {
        final hash = ThumbHash.encodeSync(w, h, solid(w, h));
        final result = ThumbHash.decodeSync(hash);
        expect(result.width, greaterThan(0));
        expect(result.height, greaterThan(0));
        expect(result.rgba.length, result.width * result.height * 4);
      });
    }
  });

  group('truncated hashes throw ArgumentError', () {
    test('empty and sub-header hashes', () {
      for (var len = 0; len < 5; len++) {
        expect(
          () => ThumbHash.decodeSync(Uint8List(len)),
          throwsValidationError,
          reason: '$len bytes',
        );
      }
    });

    for (final alpha in [false, true]) {
      test('every truncation of a valid ${alpha ? 'alpha' : 'opaque'} hash',
          () {
        final full =
            ThumbHash.encodeSync(64, 48, solid(64, 48, a: alpha ? 128 : 255));

        // Regression: any of these used to surface as a RangeError from an
        // out-of-bounds read instead of the documented ArgumentError.
        for (var len = 0; len < full.length; len++) {
          expect(
            () => ThumbHash.decodeSync(
              Uint8List.sublistView(full, 0, len),
            ),
            throwsValidationError,
            reason: 'truncated to $len of ${full.length} bytes',
          );
        }
      });
    }

    test('header claiming more coefficients than the bytes provide', () {
      // Foreign implementations may emit lCount values this encoder never
      // produces. Patch the count field (bits 24-26 of the first header word)
      // to its maximum so the header demands more AC data than follows.
      final patched = ThumbHash.encodeSync(48, 64, solid(48, 64));
      patched[3] |= 7;
      expect(
        () => ThumbHash.decodeSync(patched),
        throwsValidationError,
        reason: 'lCount patched to 7 without extra bytes',
      );
    });

    test('the exact required length decodes', () {
      final full = ThumbHash.encodeSync(64, 48, solid(64, 48));
      expect(ThumbHash.decodeSync(full).width, greaterThan(0));
    });

    test('extra trailing bytes are tolerated', () {
      final full = ThumbHash.encodeSync(64, 48, solid(64, 48));
      final padded = Uint8List(full.length + 4)..setRange(0, full.length, full);
      final expected = ThumbHash.decodeSync(full);
      final actual = ThumbHash.decodeSync(padded);
      expect(actual.rgba, expected.rgba);
    });
  });

  group('baseSize validation', () {
    final hash = ThumbHash.encodeSync(100, 30, solid(100, 30));

    test('zero and negative values throw ArgumentError', () {
      for (final size in [0, -1, -32]) {
        expect(
          () => ThumbHash.decodeSync(hash, baseSize: size),
          throwsA(
              isA<ArgumentError>().having((e) => e.name, 'name', 'baseSize')),
          reason: 'baseSize $size',
        );
      }
    });

    test('baseSize 1 never produces a zero-pixel dimension', () {
      // Regression: the short side used to round down to zero for hashes
      // with an aspect ratio steeper than the decoder's coefficient ratio.
      final result = ThumbHash.decodeSync(hash, baseSize: 1);
      expect(result.width, greaterThanOrEqualTo(1));
      expect(result.height, greaterThanOrEqualTo(1));
      expect(result.rgba.length, result.width * result.height * 4);
    });
  });
}
