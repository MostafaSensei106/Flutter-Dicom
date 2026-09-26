import '../../domain/dicom_color_map.dart';
import '../../domain/dicom_pixel_data.dart';
import '../../domain/dicom_windowing.dart';

/// Renderer port — backends (`Fragment` / GPU / software) hide here.
abstract interface class DicomRenderer {
  Future<DicomRenderResult> render(
    final DicomPixelData pixels, {
    final DicomRenderOptions options = const DicomRenderOptions(),
  });
}

/// Render tuning: window + color map + inversion.
final class DicomRenderOptions {
  const DicomRenderOptions({
    this.window,
    this.colorMap = DicomColorMap.grayscale,
    this.invert = false,
  });

  final DicomWindow? window;
  final DicomColorMap colorMap;
  final bool invert;
}

/// Opaque render handle produced by the backend.
final class DicomRenderResult {
  const DicomRenderResult({required this.width, required this.height});
  final int width;
  final int height;
}
