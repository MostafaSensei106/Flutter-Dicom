import 'dicom_metadata.dart';
import 'dicom_pixel_data.dart';

/// Parse options — metadata-only mode skips pixel decoding entirely.
final class DicomParseOptions {
  const DicomParseOptions({this.metadataOnly = false});
  final bool metadataOnly;
}

/// Decode tuning knobs.
final class DicomDecodeOptions {
  const DicomDecodeOptions({this.skipPixels = false, this.frameIndex = 0});
  final bool skipPixels;
  final int frameIndex;
}

/// A single frame handle. Pixel buffers stay lazy — the parser must not
/// load all frames of a 400-frame series into memory.
final class DicomFrame {
  const DicomFrame({
    required this.index,
    required this.metadata,
    this.pixelData,
  });

  final int index;
  final DicomMetadata metadata;
  final DicomPixelData? pixelData;
}

/// Lightweight reference used by series / volume builders.
final class DicomFrameReference {
  const DicomFrameReference({required this.index, this.label});
  final int index;
  final String? label;
}
