import 'dart:typed_data';

/// Fills a w x h RGBA buffer with a single colour.
Uint8List solid(int w, int h,
    {int r = 180, int g = 90, int b = 45, int a = 255}) {
  final bytes = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    bytes[i * 4] = r;
    bytes[i * 4 + 1] = g;
    bytes[i * 4 + 2] = b;
    bytes[i * 4 + 3] = a;
  }
  return bytes;
}

/// Deterministic RGBA gradient.
///
/// The encode goldens in encode_golden_test.dart are pinned to this exact
/// formula — do not change it.
Uint8List gradient(int w, int h, {bool alpha = false}) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      b[i] = (x * 255) ~/ (w - 1);
      b[i + 1] = (y * 255) ~/ (h - 1);
      b[i + 2] = ((x + y) * 255) ~/ (w + h - 2);
      b[i + 3] = alpha ? 128 + (x * 127) ~/ (w - 1) : 255;
    }
  }
  return b;
}
