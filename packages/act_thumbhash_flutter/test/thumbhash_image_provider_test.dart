import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:act_thumbhash_flutter/act_thumbhash_flutter.dart';

/// Reference hash from the ThumbHash project; decodes to a 23x32 image.
const referenceHash = '1QcSHQRnh493V4dIh4eXh1h4kJUI';

/// Resolves [provider] and returns the first frame's [ImageInfo].
Future<ImageInfo> resolveImage(ThumbHashImageProvider provider) {
  final completer = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info);
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bytes = Uint8List.fromList([for (var i = 0; i < 25; i++) i * 9 % 256]);

  group('equality and hashCode', () {
    test('equal for identical bytes in different instances', () {
      final a = ThumbHashImageProvider(Uint8List.fromList(bytes));
      final b = ThumbHashImageProvider(Uint8List.fromList(bytes));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('unequal for different bytes', () {
      final other = Uint8List.fromList(bytes);
      other[10] ^= 0xFF;
      expect(
        ThumbHashImageProvider(bytes),
        isNot(equals(ThumbHashImageProvider(other))),
      );
    });

    test('unequal for different scale', () {
      expect(
        ThumbHashImageProvider(bytes),
        isNot(equals(ThumbHashImageProvider(bytes, scale: 2.0))),
      );
    });

    test('unequal for different baseSize', () {
      expect(
        ThumbHashImageProvider(bytes),
        isNot(equals(ThumbHashImageProvider(bytes, baseSize: 64))),
      );
    });

    test('unequal for different length', () {
      expect(
        ThumbHashImageProvider(bytes),
        isNot(equals(ThumbHashImageProvider(bytes.sublist(0, 20)))),
      );
    });

    test('equal when one hash is an unaligned view into a larger buffer', () {
      // Regression: comparison used to go through Uint64List views, which
      // throw for views not aligned to 8 bytes (and do not exist on the web).
      final buffer = Uint8List(bytes.length + 3);
      buffer.setRange(3, buffer.length, bytes);
      final view = Uint8List.sublistView(buffer, 3);

      final a = ThumbHashImageProvider(view);
      final b = ThumbHashImageProvider(Uint8List.fromList(bytes));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('construction', () {
    test('fromBase64 accepts unpadded base64', () {
      final provider = ThumbHashImageProvider.fromBase64(referenceHash);
      expect(provider.hash, hasLength(21));
    });

    test('toImageProvider extension carries scale and baseSize', () {
      final provider = bytes.toImageProvider(scale: 2.0, baseSize: 48);
      expect(provider.hash, same(bytes));
      expect(provider.scale, 2.0);
      expect(provider.baseSize, 48);
    });

    test('obtainKey resolves synchronously to itself', () {
      final provider = ThumbHashImageProvider(bytes);
      ThumbHashImageProvider? key;
      provider.obtainKey(ImageConfiguration.empty).then((k) => key = k);
      expect(key, same(provider));
    });
  });

  group('image loading', () {
    test('decodes the reference hash to a 23x32 image', () async {
      final info =
          await resolveImage(ThumbHashImageProvider.fromBase64(referenceHash));
      expect(info.image.width, 23);
      expect(info.image.height, 32);
      expect(info.scale, 1.0);
      info.dispose();
    });

    test('baseSize controls the decoded dimensions', () async {
      final info = await resolveImage(
        ThumbHashImageProvider.fromBase64(referenceHash, baseSize: 64),
      );
      // The reference hash decodes to 23x32 at the default baseSize of 32,
      // so doubling it doubles the output.
      expect(info.image.width, 46);
      expect(info.image.height, 64);
      info.dispose();
    });

    test('propagates scale into ImageInfo', () async {
      final info = await resolveImage(
        ThumbHashImageProvider.fromBase64(referenceHash, scale: 3.0),
      );
      expect(info.scale, 3.0);
      info.dispose();
    });

    test('reports an error for an invalid hash', () async {
      final provider = ThumbHashImageProvider(Uint8List(3));
      await expectLater(resolveImage(provider), throwsArgumentError);
    });

    test('reports an error for an invalid baseSize instead of hanging',
        () async {
      final provider =
          ThumbHashImageProvider.fromBase64(referenceHash, baseSize: 0);
      await expectLater(resolveImage(provider), throwsArgumentError);
    });
  });
}
