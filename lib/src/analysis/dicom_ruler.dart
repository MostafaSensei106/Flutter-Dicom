import 'dart:math' as math;

import '../domain/dicom_geometry.dart';

/// Point-to-point measurement (pixels + physical millimeters).
final class DicomRuler {
  /// Creates a stateless point-to-point ruler.
  const DicomRuler();

  /// Measures the distance between [start] and [end] using [geometry].
  DicomMeasurement measure(
    final DicomPoint start,
    final DicomPoint end,
    final DicomGeometry geometry,
  ) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final dist = math.sqrt(dx * dx + dy * dy);
    return DicomMeasurement(
      pixelDistance: dist,
      millimeters: geometry.pixelsToMillimeters(dist),
    );
  }
}

/// A single distance measurement.
final class DicomMeasurement {
  /// Creates a measurement with a pixel distance and optional millimeters.
  const DicomMeasurement({required this.pixelDistance, this.millimeters});

  /// Distance in image pixels.
  final double pixelDistance;

  /// `null` when pixel spacing is unknown.
  final double? millimeters;
}
