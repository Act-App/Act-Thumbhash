@TestOn('vm')
library;

import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:act_thumbhash/act_thumbhash.dart';

enum _Orientation { square, landscape, portrait }

void main() {
  const fixtures = {
    1: _Orientation.square,
    2: _Orientation.landscape,
    3: _Orientation.portrait,
  };

  for (final MapEntry(key: fileNum, value: orientation) in fixtures.entries) {
    // Load and encode each fixture once; both baseSize variants share it.
    final file = File('test/fixtures/test_image_$fileNum.png');
    final decoded = img.decodePng(file.readAsBytesSync())!;
    final rgba = decoded.convert(numChannels: 4).getBytes();
    final hash = ThumbHash.encodeSync(decoded.width, decoded.height, rgba);

    for (final baseSize in [null, 128]) {
      final label = baseSize == null ? '' : ', baseSize: $baseSize';
      test('encode then decode roundtrip test_image_$fileNum.png$label', () {
        final result = ThumbHash.decodeSync(hash, baseSize: baseSize ?? 32);

        switch (orientation) {
          case _Orientation.square:
            expect(result.height, equals(result.width));
            if (baseSize != null) {
              expect(result.width, equals(baseSize));
              expect(result.height, equals(baseSize));
            }
          case _Orientation.landscape:
            expect(result.height, lessThan(result.width));
            if (baseSize != null) {
              expect(result.width, equals(baseSize));
            }
          case _Orientation.portrait:
            expect(result.height, greaterThan(result.width));
            if (baseSize != null) {
              expect(result.height, equals(baseSize));
            }
        }

        expect(result.width, greaterThan(0));
        expect(result.height, greaterThan(0));
        expect(result.rgba.length, equals(result.width * result.height * 4));

        // Save the decoded result for visual inspection. The PNGs are
        // committed and CI diffs them, so the last write per fixture (the
        // baseSize-128 variant) must stay reproducible.
        final output = img.Image.fromBytes(
          width: result.width,
          height: result.height,
          bytes: result.rgba.buffer,
          numChannels: 4,
        );
        File('test/fixtures/output_image_$fileNum.png')
            .writeAsBytesSync(img.encodePng(output));
      });
    }
  }
}
