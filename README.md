# act-thumbhash
## Introduction
The act-thumbhash libraries implement the
[Thumbhash](https://evanw.github.io/thumbhash/) image placeholder generation
algorithm invented by [Evan Wallace](https://madebyevan.com/) for dart & flutter.

This algorithm is used to calculate a small binary hash representing an image
using a [Discrete Cosine
Transform](https://en.wikipedia.org/wiki/Discrete_cosine_transform). The hash
can then be used to generate a lossy representation of the original image.

The main use case is progressive loading of a web page containing lots of
images, e.g. a photo gallery. Store the hash of each image in your database,
and send it to your client side. On the client side, generate a placeholder image 
from the hash. Then load the original image asynchronously.

## Installation

```yaml
dependencies:
<<<<<<< HEAD
  act_thumbhash: ^1.0.0 # For non Flutter projects
  act_thumbhash_flutter: ^1.0.0  # For Flutter projects
=======
  act_thumbhash: ^1.0.0-dev.1
  act_thumbhash_flutter: ^1.0.0-dev.1  # For Flutter projects
>>>>>>> 2997514 (add examples)
```

## Usage
### Dart (Core Library)
Encoding an image to a ThumbHash
```dart
import 'dart:typed_data';
import 'package:act_thumbhash/act_thumbhash.dart';

// Your RGBA image data (4 bytes per pixel: R, G, B, A)
final Uint8List rgba = getImageRgbaBytes();
final int width = 100;
final int height = 75;

// Async (recommended for UI applications)
final hash = await ThumbHash.encodeAsync(width, height, rgba);

// Sync (for non-UI contexts)
final hash = ThumbHash.encodeSync(width, height, rgba);

// Store the hash (typically 25-35 bytes) in your database
// or encode as base64 for transport
final base64Hash = base64.encode(hash);
```

Decoding a ThumbHash to an image
```dart
import 'package:act_thumbhash/act_thumbhash.dart';

final Uint8List hash = getStoredHash();

// Async (recommended)
final result = await ThumbHash.decodeAsync(hash);

// Sync
final result = ThumbHash.decodeSync(hash);

// Access the decoded image
print('Size: ${result.width}x${result.height}');
final Uint8List rgba = result.rgba;  // RGBA pixel data
```

Customizing output size
```dart
// Larger placeholder for hero images
final result = await ThumbHash.decodeAsync(hash, baseSize: 64);

// Smaller for list thumbnails
final result = await ThumbHash.decodeAsync(hash, baseSize: 24);
```

### Flutter
Using ThumbHashImageProvider
```dart
import 'package:act_thumbhash_flutter/act_thumbhash_flutter.dart';

final Uint8List hashBytes = getStoredHash();
// From bytes
Image(
  image: ThumbHashImageProvider(hashBytes),
  fit: BoxFit.cover,
)

// From base64 string (common when receiving from API)
Image(
  image: ThumbHashImageProvider.fromBase64('1QcSHQRnh493V4dIh4eXh1h4kJUI'),
  fit: BoxFit.cover,
)

// Using the extension method
Image(
  image: hashBytes.toImageProvider(),
  fit: BoxFit.cover,
)
```

With FadeInImage
```dart
FadeInImage(
  placeholder: ThumbHashImageProvider.fromBase64(thumbHash),
  image: NetworkImage(imageUrl),
  fit: BoxFit.cover,
  fadeInDuration: const Duration(milliseconds: 200),
)
```

# Licensing
act-thumbhash is open source software distributed under the
[MIT](https://opensource.org/license/mit) license.
