import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:act_thumbhash/act_thumbhash.dart';

/// An [ImageProvider] that decodes a ThumbHash and provides proper caching.
///
/// Unlike `MemoryImage`, this provider correctly implements `==` and `hashCode`
/// based on the ThumbHash content, enabling Flutter's `ImageCache` to work
/// properly. This means identical ThumbHashes will be decoded only once and
/// reused from cache.
@immutable
class ThumbHashImageProvider extends ImageProvider<ThumbHashImageProvider> {
  /// Creates a ThumbHash image provider.
  ///
  /// [hash] is the ThumbHash bytes.
  /// [scale] is the scale to place in the [ImageInfo] object (default: 1.0).
  /// [baseSize] is the length in pixels of the decoded placeholder's longer
  /// side (default: 32).
  const ThumbHashImageProvider(
    this.hash, {
    this.scale = 1.0,
    this.baseSize = 32,
  });

  /// Creates a ThumbHash image provider from a base64-encoded string.
  ///
  /// [base64Hash] is the ThumbHash encoded as a base64 string.
  /// [scale] is the scale to place in the [ImageInfo] object (default: 1.0).
  /// [baseSize] is the length in pixels of the decoded placeholder's longer
  /// side (default: 32).
  factory ThumbHashImageProvider.fromBase64(
    String base64Hash, {
    double scale = 1.0,
    int baseSize = 32,
  }) {
    return ThumbHashImageProvider(
      base64.decode(base64.normalize(base64Hash)),
      scale: scale,
      baseSize: baseSize,
    );
  }

  /// The ThumbHash bytes to decode.
  final Uint8List hash;

  /// The scale to place in the [ImageInfo] object of the image.
  final double scale;

  /// The length in pixels of the decoded placeholder's longer side.
  ///
  /// Placeholders are blurry by nature, so the default of 32 is usually
  /// enough; raise it for large hero images if banding becomes visible.
  final int baseSize;

  @override
  Future<ThumbHashImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<ThumbHashImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    ThumbHashImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_loadAsync(key));
  }

  Future<ImageInfo> _loadAsync(ThumbHashImageProvider key) async {
    assert(key == this);

    // Decode ThumbHash to RGBA (runs in isolate)
    final result = await ThumbHash.decodeAsync(hash, baseSize: baseSize);

    // Convert RGBA to ui.Image. The future-based descriptor API is used
    // instead of ui.decodeImageFromPixels, whose success-only callback would
    // leave the image stream hanging forever if the engine rejects the data.
    final buffer = await ui.ImmutableBuffer.fromUint8List(result.rgba);
    try {
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: result.width,
        height: result.height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      try {
        final codec = await descriptor.instantiateCodec();
        try {
          final frame = await codec.getNextFrame();
          return ImageInfo(image: frame.image, scale: scale);
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  /// Content-based equality comparison.
  ///
  /// Two [ThumbHashImageProvider] instances are equal if their hash bytes
  /// are identical (content-wise) and their [scale] and [baseSize] are the
  /// same.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;

    return other is ThumbHashImageProvider &&
        scale == other.scale &&
        baseSize == other.baseSize &&
        listEquals(hash, other.hash);
  }

  /// Content-based hash code.
  ///
  /// Computed from the actual bytes of the ThumbHash, not the object identity.
  @override
  int get hashCode => Object.hash(Object.hashAll(hash), scale, baseSize);

  @override
  String toString() => '${objectRuntimeType(this, 'ThumbHashImageProvider')}'
      '(${hash.length} bytes, scale: $scale, baseSize: $baseSize)';
}

/// Extension to easily get a [ThumbHashImageProvider] from a [Uint8List].
extension ThumbHashImageProviderExtension on Uint8List {
  /// Creates a [ThumbHashImageProvider] from this ThumbHash.
  ///
  /// ```dart
  /// final provider = myThumbHashBytes.toImageProvider();
  /// ```
  ThumbHashImageProvider toImageProvider(
      {double scale = 1.0, int baseSize = 32}) {
    return ThumbHashImageProvider(this, scale: scale, baseSize: baseSize);
  }
}
