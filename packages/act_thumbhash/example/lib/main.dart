import 'dart:convert';
import 'dart:typed_data';
import 'package:act_thumbhash/act_thumbhash.dart';

void main() {
  print('=== ThumbHash Example ===\n');

  // Create a simple 4x4 red image (RGBA format)
  final width = 4;
  final height = 4;
  final rgba = Uint8List(width * height * 4);

  // Fill with red pixels (R=255, G=0, B=0, A=255)
  for (var i = 0; i < rgba.length; i += 4) {
    rgba[i] = 255; // R
    rgba[i + 1] = 0; // G
    rgba[i + 2] = 0; // B
    rgba[i + 3] = 255; // A
  }

  // Encode to ThumbHash
  final hash = ThumbHash.encodeSync(width, height, rgba);
  print('Original image: ${width}x$height red square');
  print('ThumbHash size: ${hash.length} bytes');
  print('ThumbHash (base64): ${base64Encode(hash)}\n');

  // Decode back to image
  final decoded = ThumbHash.decodeSync(hash);
  print('Decoded image: ${decoded.width}x${decoded.height}');
}
