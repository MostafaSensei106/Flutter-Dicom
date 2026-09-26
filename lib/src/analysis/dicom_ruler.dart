import 'dart:math' as math;

import '../domain/dicom_geometry.dart';

/// Point-to-point measurement (pixels + physical millimeters).
final class DicomRuler {
  const DicomRuler();

  DicomMeasurement measure(
    DicomPoint start,
    DicomPoint end,
    DicomGeometry geometry,
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
  const DicomMeasurement({required this.pixelDistance, this.millimeters});

  final double pixelDistance;

  /// `null` when pixel spacing is unknown.
  final double? millimeters;
}
