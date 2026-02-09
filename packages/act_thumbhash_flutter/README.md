# act_thumbhash_flutter

Flutter widgets and image providers for the [ThumbHash](https://evanw.github.io/thumbhash/) image placeholder algorithm. Built on top of [act_thumbhash](https://github.com/Act-App/Act-Thumbhash/tree/main/packages/act_thumbhash).

ThumbHash encodes an image into a compact binary hash (~25–35 bytes), which can be decoded into a small lossy placeholder. Use it to show instant previews while full images load over the network.

## Installation

```yaml
dependencies:
  act_thumbhash_flutter: ^1.0.0-dev.2
```

This package depends on `act_thumbhash` and will pull it in automatically.

## Usage

### ThumbHashImageProvider

Use it anywhere Flutter expects an `ImageProvider`:

```dart
import 'package:act_thumbhash_flutter/act_thumbhash_flutter.dart';

// From raw bytes
Image(
  image: ThumbHashImageProvider(hashBytes),
  fit: BoxFit.cover,
)

// From a base64 string (common when receiving from an API)
Image(
  image: ThumbHashImageProvider.fromBase64('1QcSHQRnh493V4dIh4eXh1h4kJUI'),
  fit: BoxFit.cover,
)

// Using the extension method on Uint8List
Image(
  image: hashBytes.toImageProvider(),
  fit: BoxFit.cover,
)
```

### Progressive image loading with FadeInImage

```dart
FadeInImage(
  placeholder: ThumbHashImageProvider.fromBase64(thumbHash),
  image: NetworkImage(imageUrl),
  fit: BoxFit.cover,
  fadeInDuration: const Duration(milliseconds: 200),
)
```

### Caching

`ThumbHashImageProvider` integrates with Flutter's built-in `ImageCache`. Multiple widgets using the same hash will share a single decoded image — no duplicate decoding or memory usage.

## License

MIT — see [LICENSE](https://github.com/Act-App/Act-Thumbhash/blob/main/LICENSE).