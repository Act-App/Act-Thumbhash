import 'dart:async';
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
  const ThumbHashImageProvider(
    this.hash, {
    this.scale = 1.0,
  });

  /// Creates a ThumbHash image provider from a base64-encoded string.
  ///
  /// [base64Hash] is the ThumbHash encoded as a base64 string.
  /// [scale] is the scale to place in the [ImageInfo] object (default: 1.0).
  factory ThumbHashImageProvider.fromBase64(
    String base64Hash, {
    double scale = 1.0,
  }) {
    return ThumbHashImageProvider(
      base64.decode(base64.normalize(base64Hash)),
      scale: scale,
    );
  }

  /// The ThumbHash bytes to decode.
  final Uint8List hash;

  /// The scale to place in the [ImageInfo] object of the image.
  final double scale;

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

    final image = await _decodeThumbHashToUiImage(hash);
    return ImageInfo(image: image, scale: scale);
  }

  /// Decodes a ThumbHash to a Flutter [ui.Image].
  static Future<ui.Image> _decodeThumbHashToUiImage(Uint8List hash) async {
    final completer = Completer<ui.Image>();

    // Decode ThumbHash to RGBA (runs in isolate)
    final result = await ThumbHash.decodeAsync(hash);

    // Convert RGBA to ui.Image
    ui.decodeImageFromPixels(
      result.rgba,
      result.width,
      result.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );

    return completer.future;
  }

  /// Content-based equality comparison.
  ///
  /// Two [ThumbHashImageProvider] instances are equal if their hash bytes
  /// are identical (content-wise) and their scale is the same.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;

    return other is ThumbHashImageProvider &&
        scale == other.scale &&
        listEquals(hash, other.hash);
  }

  /// Content-based hash code.
  ///
  /// Computed from the actual bytes of the ThumbHash, not the object identity.
  @override
  int get hashCode => Object.hash(Object.hashAll(hash), scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'ThumbHashImageProvider')}(${hash.length} bytes, scale: $scale)';
}

/// Extension to easily get a [ThumbHashImageProvider] from a [Uint8List].
extension ThumbHashImageProviderExtension on Uint8List {
  /// Creates a [ThumbHashImageProvider] from this ThumbHash.
  ///
  /// ```dart
  /// final provider = myThumbHashBytes.toImageProvider();
  /// ```
  ThumbHashImageProvider toImageProvider({double scale = 1.0}) {
    return ThumbHashImageProvider(this, scale: scale);
  }
}
