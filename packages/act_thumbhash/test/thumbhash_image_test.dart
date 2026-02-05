import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:act_thumbhash/act_thumbhash.dart';

void testHelper(int fileNum, {int baseSize = 0}) {
    // Load and decode image to RGBA
    final file = File('test/fixtures/test_image_' + fileNum.toString() + '.png');
    final decoded = img.decodePng(file.readAsBytesSync())!;
    //print('Orig size: ${decoded.width}x${decoded.height}');
    final rgba = Uint8List.fromList(
      decoded.convert(numChannels: 4).getBytes(),
    );

    // Encode
    final hash = ThumbHash.encodeSync(decoded.width, decoded.height, rgba);
    //final stringHash = base64.encode(hash);
    //print('Hash length: ${hash.length} bytes');
    //print('Base64: ${stringHash}');


    ThumbHashDecodeResult result;
    // Decode
    if (baseSize == 0) {
      result = ThumbHash.decodeSync(hash);
    } else {
      result = ThumbHash.decodeSync(hash, baseSize: baseSize);
    }
    //print('Decoded size: ${result.width}x${result.height}');
    if (fileNum == 1) {
      expect(result.height, equals(result.width));
      if (baseSize != 0) {
        expect(result.height, equals(baseSize));
        expect(result.width, equals(baseSize));
      }
    } else if (fileNum == 2) {
      expect(result.height, lessThan(result.width));
      if (baseSize != 0) {
        expect(result.width, equals(baseSize));
      }
    } else if (fileNum == 3) {
      expect(result.height, greaterThan(result.width));
      expect(result.height, equals(baseSize));
    }

    expect(result.width, greaterThan(0));
    expect(result.height, greaterThan(0));
    expect(result.rgba.length, equals(result.width * result.height * 4));
    
    

    // Save decoded result for visual inspection
    final output = img.Image.fromBytes(
      width: result.width,
      height: result.height,
      bytes: result.rgba.buffer,
      numChannels: 4,
    );
    File('test/fixtures/output_image_' + fileNum.toString() + '.png').writeAsBytesSync(img.encodePng(output));
}

void main() {

  test('encode then decode roundtrip test_image_1.png', () {
    testHelper(1);
  });

  test('encode then decode roundtrip test_image_2.png', () {
    testHelper(2);
  });

  test('encode then decode roundtrip test_image_3.png', () {
    testHelper(3);
  });

  test('encode then decode roundtrip test_image_1.png, baseSize: 128', () {
    testHelper(1, baseSize: 128);
  });

  test('encode then decode roundtrip test_image_2.png, baseSize: 128', () {
    testHelper(2, baseSize: 128);
  });

  test('encode then decode roundtrip test_image_3.png, baseSize: 128', () {
    testHelper(3, baseSize: 128);
  });
}