import 'dart:typed_data';

import '../../domain/dicom_pixel_data.dart';

/// Export target formats.
enum DicomExportFormat {
  png,
  jpeg,
  tiff,
}

/// Document-level export (DICOM writing).
enum DicomDocumentFormat {
  secondaryCapture,
}

/// Export tuning.
final class DicomExportOptions {
  const DicomExportOptions({this.quality = 90});
  final int quality;
}

/// Exporter port — one strategy per format, no format `switch` in callers.
abstract interface class DicomExporter {
  Future<Uint8List> export(
    DicomPixelData pixels, {
    required DicomExportFormat format,
    DicomExportOptions options = const DicomExportOptions(),
  });
}
