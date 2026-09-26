import 'dart:typed_data';

import '../../domain/dicom_pixel_data.dart';

/// Export target formats.
enum DicomExportFormat {
  /// Encoded PNG image.
  png,

  /// Encoded JPEG image.
  jpeg,

  /// Encoded TIFF image.
  tiff,
}

/// Document-level export (DICOM writing).
enum DicomDocumentFormat {
  /// Secondary capture document.
  secondaryCapture,
}

/// Export tuning.
final class DicomExportOptions {
  /// Creates export tuning with JPEG [quality].
  const DicomExportOptions({this.quality = 90});

  /// Encoding quality used by lossy formats.
  final int quality;
}

/// Exporter port — one strategy per format, no format `switch` in callers.
abstract interface class DicomExporter {
  /// Exports [pixels] to [format] using [options].
  Future<Uint8List> export(
    final DicomPixelData pixels, {
    required final DicomExportFormat format,
    final DicomExportOptions options = const DicomExportOptions(),
  });
}
