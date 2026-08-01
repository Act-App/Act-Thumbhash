@TestOn('vm')
library;

import 'dart:convert';
import 'package:test/test.dart';
import 'package:act_thumbhash/act_thumbhash.dart';

import 'helpers.dart';

/// Exact encoder output, base64-encoded, keyed by (width, height, hasAlpha).
///
/// These pin the encoder byte-for-byte: any change to the DCT, the coefficient
/// layout or the header packing shows up here as a diff that must be reviewed
/// deliberately. Kept VM-only because `dart:math` trigonometry may differ from
/// the browser's in the last ulp, which can flip a coefficient rounded exactly
/// at a quantization boundary.
const goldens = {
  (64, 64, false): 'HwgOBxqAh4dweHeIh3iHiId3+PmYgI8H',
  (128, 128, false): 'HwgOBxqAh4eAh4d4eHh4iIeHCA/3gI8H',
  (100, 75, true): '4ReKDJQrkIeAh3h4+AaJkG8HeHiIeIh4Bw==',
  (100, 30, false): 'H/gRIpqAh4eCiIiIj3AI+Hg=',
  (30, 100, true): 'IRiOGhQrgpCHd4iQbwj5doCHiIh4eIc=',
  (33, 20, false): '3/cRFJqAh4dxeHh4iIePcAj4eA==',
  // Exercises the >128px downscale path.
  (200, 150, false): '3wcODZqAh4dxeId3d3h4iI+ACPiH',
};

void main() {
  group('encoder output is stable', () {
    for (final MapEntry(key: (w, h, alpha), value: expected)
        in goldens.entries) {
      test('${w}x$h ${alpha ? 'with alpha' : 'opaque'}', () {
        final hash = ThumbHash.encodeSync(w, h, gradient(w, h, alpha: alpha));
        expect(base64.encode(hash), expected);
      });
    }
  });
}
