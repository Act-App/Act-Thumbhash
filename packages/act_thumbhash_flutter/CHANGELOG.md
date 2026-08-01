## Unreleased

- **Feat**: Web support. Provider equality no longer relies on `Uint64List`,
  which dart2js does not support.
- **Fix**: Comparing providers whose hash bytes are a view into a larger
  buffer at an offset not aligned to 8 bytes no longer throws.

## 1.0.0-dev.2

- Documentation and packaging updates

## 1.0.0-dev.1

- Initial pre-release
- `ThumbHashImageProvider` for use with Flutter's `Image` widget
- `fromBase64` factory for decoding base64-encoded hashes
- `toImageProvider()` extension method on `Uint8List`
- Integration with Flutter's `ImageCache`
