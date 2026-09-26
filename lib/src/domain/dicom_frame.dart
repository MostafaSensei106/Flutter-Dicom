import '../../flutter_dicom.dart';

/// Parse options — metadata-only mode skips pixel decoding entirely.
final class DicomParseOptions {
  /// Creates parse options.
  const DicomParseOptions({this.metadataOnly = false});

  /// Skips pixel decoding when true.
  final bool metadataOnly;
}

/// Decode tuning knobs.
final class DicomDecodeOptions {
  /// Creates decode options.
  const DicomDecodeOptions({this.skipPixels = false, this.frameIndex = 0});

  /// Skips pixel buffers when true.
  final bool skipPixels;

  /// Frame index to decode.
  final int frameIndex;
}

/// A single frame handle. Pixel buffers stay lazy — the parser must not
/// load all frames of a 400-frame series into memory.
final class DicomFrame {
  /// Creates a frame handle.
  const DicomFrame({
    required this.index,
    required this.metadata,
    this.pixelData,
  });

  /// Zero-based frame index.
  final int index;

  /// Typed header metadata for the frame.
  final DicomMetadata metadata;

  /// Decoded pixels, when loaded.
  final DicomPixelData? pixelData;
}

/// Lightweight reference used by series / volume builders.
final class DicomFrameReference {
  /// Creates a frame reference.
  const DicomFrameReference({
    required this.index,
    this.label,
    this.position,
    this.instanceNumber,
    this.sliceLocation,
  });

  /// Zero-based frame index.
  final int index;

  /// Optional display label.
  final String? label;

  /// Image position (0020,0032) of the slice, when known.
  final DicomPosition? position;

  /// Instance Number (0020,0013) of the slice, when known.
  final int? instanceNumber;

  /// Slice Location (0020,1041) of the slice, when known.
  final double? sliceLocation;
}
