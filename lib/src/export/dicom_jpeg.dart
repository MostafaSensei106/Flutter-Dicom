import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/dicom_pixel_data.dart';
import '../domain/dicom_windowing.dart';

/// JPEG exporter writing baseline grayscale JPEG via `package:image`.
///
/// Pixel values are mapped through [window] exactly like the PNG exporter
/// (what you see is what you get); [quality] follows the encoder's 1–100
/// scale (IJG-style quantization under the hood).
final class JpegDicomExporter {
  /// Creates a JPEG exporter.
  const JpegDicomExporter();

  /// Exports [pixels] through [window] as baseline grayscale JPEG.
  Future<Uint8List> exportWindowed(
    final DicomPixelData pixels,
    final DicomWindow window, {
    final int quality = 90,
  }) async {
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
    return img.encodeJpg(image, quality: quality.clamp(1, 100));
  }
}
