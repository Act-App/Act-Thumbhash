import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:act_thumbhash/act_thumbhash.dart';

import 'helpers.dart';

void main() {
  group('ThumbHash', () {
    // A simple test image (4x4 solid red); no test mutates it.
    final testWidth = 4;
    final testHeight = 4;
    final testRgba = solid(testWidth, testHeight, r: 255, g: 0, b: 0);

    test('encodeSync produces non-empty hash', () {
      final hash = ThumbHash.encodeSync(testWidth, testHeight, testRgba);
      expect(hash, isNotEmpty);
      expect(hash.length, greaterThanOrEqualTo(5));
    });

    test('decodeSync produces valid image', () {
      final hash = ThumbHash.encodeSync(testWidth, testHeight, testRgba);
      final result = ThumbHash.decodeSync(hash);

      expect(result.width, greaterThan(0));
      expect(result.height, greaterThan(0));
      expect(result.rgba.length, equals(result.width * result.height * 4));
    });

    test('encodeAsync produces same result as encodeSync', () async {
      final hashSync = ThumbHash.encodeSync(testWidth, testHeight, testRgba);
      final hashAsync =
          await ThumbHash.encodeAsync(testWidth, testHeight, testRgba);

      expect(hashAsync, equals(hashSync));
    });

    test('decodeAsync produces same result as decodeSync', () async {
      final hash = ThumbHash.encodeSync(testWidth, testHeight, testRgba);

      final resultSync = ThumbHash.decodeSync(hash);
      final resultAsync = await ThumbHash.decodeAsync(hash);

      expect(resultAsync.width, equals(resultSync.width));
      expect(resultAsync.height, equals(resultSync.height));
      expect(resultAsync.rgba, equals(resultSync.rgba));
    });

    test('image too large', () {
      final largeRgba = Uint8List(150 * 150 * 4);
      final hash = ThumbHash.encodeSync(150, 150, largeRgba);
      final result = ThumbHash.decodeSync(hash);
      expect(hash, isNotEmpty);
      expect(hash.length, greaterThanOrEqualTo(5));
      expect(result.width, lessThan(129));
      expect(result.height, lessThan(129));
    });

    test('throws on hash too short', () {
      final shortHash = Uint8List(3);
      expect(
        () => ThumbHash.decodeSync(shortHash),
        throwsArgumentError,
      );
    });

    test('encodes and decodes image with alpha', () {
      // Semi-transparent red
      final alphaRgba =
          solid(testWidth, testHeight, r: 255, g: 0, b: 0, a: 128);

      final hash = ThumbHash.encodeSync(testWidth, testHeight, alphaRgba);
      final result = ThumbHash.decodeSync(hash);

      expect(result.width, greaterThan(0));
      expect(result.height, greaterThan(0));
    });

    test('handles gradient image', () {
      final hash = ThumbHash.encodeSync(10, 10, gradient(10, 10));
      final result = ThumbHash.decodeSync(hash);

      expect(result.width, greaterThan(0));
      expect(result.height, greaterThan(0));
    });
  });
}
