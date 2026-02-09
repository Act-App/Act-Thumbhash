# Example

Demonstrates basic encoding and decoding with `act_thumbhash`.

Run with:
```bash
dart run example/example.dart
```

Done! Just 30 lines showing:
- Creating RGBA image data
- Encoding to ThumbHash
- Converting to base64 for storage
- Decoding back to RGBA

Output will be something like:
```
=== ThumbHash Example ===

Original image: 4x4 red square
ThumbHash size: 25 bytes
ThumbHash (base64): PxQJBwMGCQ...

Decoded image: 32x32
```