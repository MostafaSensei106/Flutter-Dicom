import '../../domain/dicom_color_map.dart';
import '../../domain/dicom_pixel_data.dart';
import '../../domain/dicom_windowing.dart';

/// Renderer port — backends (`Fragment` / GPU / software) hide here.
abstract interface class DicomRenderer {
  /// Renders [pixels] with the given [options].
  Future<DicomRenderResult> render(
    final DicomPixelData pixels, {
    final DicomRenderOptions options = const DicomRenderOptions(),
  });
}

/// Render tuning: window + color map + inversion.
final class DicomRenderOptions {
  /// Creates render tuning with an optional [window].
  const DicomRenderOptions({
    this.window,
    this.colorMap = DicomColorMap.grayscale,
    this.invert = false,
  });

  /// Window applied during rendering, or null for raw values.
  final DicomWindow? window;

  /// Color map applied during rendering.
  final DicomColorMap colorMap;

  /// Whether monochrome output is inverted.
  final bool invert;
}

/// Opaque render handle produced by the backend.
final class DicomRenderResult {
  /// Creates a render handle with [width] and [height].
  const DicomRenderResult({required this.width, required this.height});

  /// Rendered image width in pixels.
  final int width;

  /// Rendered image height in pixels.
  final int height;
}
