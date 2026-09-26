import '../../domain/dicom_frame.dart';
import '../../domain/dicom_metadata.dart';
import '../../domain/dicom_pixel_data.dart';
import '../../domain/dicom_source.dart';
import '../cache/frame_cache.dart';

/// Parser port — `parse` extracts metadata + frame handles, never full
/// pixel buffers. The public API never mentions Rust / FFI / WASM.
abstract interface class DicomParser {
  Future<DicomParseResult> parse(
    final DicomSource source, {
    final DicomParseOptions options = const DicomParseOptions(),
  });
}

/// Lazy parse result: metadata now, pixels on demand.
final class DicomParseResult {
  const DicomParseResult({required this.metadata, required this.frames});

  final DicomMetadata metadata;
  final DicomFrameProvider frames;

  int get frameCount => frames.frameCount;

  DicomFrame frame(final int index) => DicomFrame(index: index, metadata: metadata);

  /// Decodes one frame through the provider (pixels attached on return).
  Future<DicomPixelData> decodeFrame(
    final int index, {
    final DicomDecodeOptions options = const DicomDecodeOptions(),
  }) async {
    final frame = await frames.get(index);
    final pixels = frame.pixelData;
    if (pixels == null) {
      throw StateError('Provider returned frame $index without pixels');
    }
    return pixels;
  }
}

/// Lazy multi-frame access — never `List<Pixels>` for 400-frame files.
abstract interface class DicomFrameProvider {
  int get frameCount;
  Future<DicomFrame> get(final int index);
}

/// Caching provider — wraps any [DicomFrameProvider] with an LRU-style
/// [DicomFrameCache] so scrubbing never re-decodes visible frames.
final class CachedFrameProvider implements DicomFrameProvider {
  CachedFrameProvider(
      {required final DicomFrameProvider inner, final DicomFrameCache<DicomFrame>? cache})
      : _inner = inner,
        _cache = cache ?? LruFrameCache<DicomFrame>();

  final DicomFrameProvider _inner;
  final DicomFrameCache<DicomFrame> _cache;

  @override
  int get frameCount => _inner.frameCount;

  @override
  Future<DicomFrame> get(final int index) async {
    final hit = _cache.get(index);
    if (hit != null) return hit;
    final frame = await _inner.get(index);
    _cache.put(index, frame);
    return frame;
  }
}
