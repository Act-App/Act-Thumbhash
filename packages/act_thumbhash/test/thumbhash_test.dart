import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:act_thumbhash/act_thumbhash.dart';

void main() {
  group('ThumbHash', () {
    // Create a simple test image (4x4 solid red)
    final testWidth = 4;
    final testHeight = 4;
    late Uint8List testRgba;

    setUp(() {
      testRgba = Uint8List(testWidth * testHeight * 4);
      for (var i = 0; i < testWidth * testHeight; i++) {
        testRgba[i * 4] = 255; // R
        testRgba[i * 4 + 1] = 0; // G
        testRgba[i * 4 + 2] = 0; // B
        testRgba[i * 4 + 3] = 255; // A
      }
    });

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
      // Create image with partial transparency
      final alphaRgba = Uint8List(testWidth * testHeight * 4);
      for (var i = 0; i < testWidth * testHeight; i++) {
        alphaRgba[i * 4] = 255; // R
        alphaRgba[i * 4 + 1] = 0; // G
        alphaRgba[i * 4 + 2] = 0; // B
        alphaRgba[i * 4 + 3] = 128; // Semi-transparent
      }

      final hash = ThumbHash.encodeSync(testWidth, testHeight, alphaRgba);
      final result = ThumbHash.decodeSync(hash);

      expect(result.width, greaterThan(0));
      expect(result.height, greaterThan(0));
    });

    test('handles gradient image', () {
      final gradientWidth = 10;
      final gradientHeight = 10;
      final gradientRgba = Uint8List(gradientWidth * gradientHeight * 4);

      for (var y = 0; y < gradientHeight; y++) {
        for (var x = 0; x < gradientWidth; x++) {
          final i = (y * gradientWidth + x) * 4;
          gradientRgba[i] = (x * 255 ~/ gradientWidth);
          gradientRgba[i + 1] = (y * 255 ~/ gradientHeight);
          gradientRgba[i + 2] = 128;
          gradientRgba[i + 3] = 255;
        }
      }

      final hash =
          ThumbHash.encodeSync(gradientWidth, gradientHeight, gradientRgba);
      final result = ThumbHash.decodeSync(hash);

      expect(result.width, greaterThan(0));
      expect(result.height, greaterThan(0));
    });
  });
}
