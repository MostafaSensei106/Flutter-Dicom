import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/dicom_pixel_data.dart';
import '../domain/dicom_windowing.dart';

/// TIFF exporter writing uncompressed grayscale TIFF via `package:image`.
///
/// Single-channel, black-is-zero — readable by every DICOM-adjacent TIFF
/// consumer (ImageJ, Fiji, `tiffinfo`). Pixel values are mapped through
/// [window] exactly like the PNG exporter (what you see is what you get).
final class TiffDicomExporter {
  /// Creates a TIFF exporter.
  const TiffDicomExporter();

  /// Exports [pixels] through [window] as an 8-bit grayscale TIFF.
  Future<Uint8List> exportWindowed(
    final DicomPixelData pixels,
    final DicomWindow window,
  ) async {
    final image = img.Image(
      width: pixels.width,
      height: pixels.height,
      numChannels: 1,
    );
    for (var y = 0; y < pixels.height; y++) {
      for (var x = 0; x < pixels.width; x++) {
        final gray = (window.apply(pixels.modalityAt(y * pixels.width + x)) *
                255)
            .round()
            .clamp(0, 255);
        image.setPixelRgb(x, y, gray, gray, gray);
      }
    }
    return img.encodeTiff(image);
  }
}
