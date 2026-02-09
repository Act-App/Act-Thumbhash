# act_thumbhash

A pure Dart implementation of the [ThumbHash](https://evanw.github.io/thumbhash/) image placeholder algorithm by [Evan Wallace](https://madebyevan.com/).

ThumbHash encodes an image into a compact binary hash (~25–35 bytes) using a [Discrete Cosine Transform](https://en.wikipedia.org/wiki/Discrete_cosine_transform), which can then be decoded into a small lossy placeholder image. This is useful for displaying image previews while the full-resolution version loads.

For Flutter-specific widgets and image providers, see [act_thumbhash_flutter](https://github.com/Act-App/Act-Thumbhash/tree/main/packages/act_thumbhash_flutter).

## Installation

```yaml
dependencies:
  act_thumbhash: ^1.0.0-dev.2
```

## Usage

### Encoding

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:act_thumbhash/act_thumbhash.dart';

// Your RGBA image data (4 bytes per pixel)
final Uint8List rgba = getImageRgbaBytes();
final int width = 100;
final int height = 75;

// Async (recommended — runs in a separate isolate)
final hash = await ThumbHash.encodeAsync(width, height, rgba);

// Sync
final hash = ThumbHash.encodeSync(width, height, rgba);

// Encode as base64 for storage or transport
final base64Hash = base64.encode(hash);
```

Images larger than 128px on their longest side are automatically downscaled before encoding using nearest-neighbor interpolation.

### Decoding

```dart
import 'package:act_thumbhash/act_thumbhash.dart';

final Uint8List hash = getStoredHash();

// Async (recommended)
final result = await ThumbHash.decodeAsync(hash);

// Sync
final result = ThumbHash.decodeSync(hash);

print('Size: ${result.width}x${result.height}');
final Uint8List rgba = result.rgba; // RGBA pixel data
```

### Custom output size

The `baseSize` parameter controls the size of the decoded placeholder (default: 32):

```dart
// Larger placeholder for hero images
final result = await ThumbHash.decodeAsync(hash, baseSize: 64);

// Smaller for list thumbnails
final result = await ThumbHash.decodeAsync(hash, baseSize: 24);
```

## API

| Method | Description |
|---|---|
| `ThumbHash.encodeSync(width, height, rgba)` | Encode RGBA bytes to a ThumbHash |
| `ThumbHash.encodeAsync(width, height, rgba)` | Same as above, in a separate isolate |
| `ThumbHash.decodeSync(hash)` | Decode a ThumbHash to RGBA bytes |
| `ThumbHash.decodeAsync(hash)` | Same as above, in a separate isolate |

## License

MIT — see [LICENSE](https://github.com/Act-App/Act-Thumbhash/blob/main/LICENSE).