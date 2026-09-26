import 'dart:math' as math;

import '../domain/dicom_geometry.dart';
import '../domain/dicom_pixel_data.dart';

/// Measurement unit for ROI statistics.
enum DicomMeasurementUnit {
  /// Raw stored pixel values.
  raw,

  /// Values after the modality (rescale) transform.
  modalityValue,
}

/// ROI bounds in image-pixel coordinates.
final class DicomRoi {
  /// Creates an ROI covering [bounds].
  const DicomRoi(this.bounds);

  /// Bounds of the region in image-pixel coordinates.
  final DicomRect bounds;

  /// Analyzes pixels inside [bounds].
  Future<RoiStatistics> analyze(
    final DicomPixelData pixels, {
    final DicomMeasurementUnit unit = DicomMeasurementUnit.modalityValue,
  }) async {
    final x0 = bounds.left.toInt().clamp(0, pixels.width - 1);
    final y0 = bounds.top.toInt().clamp(0, pixels.height - 1);
    final x1 = (bounds.left + bounds.width).toInt().clamp(0, pixels.width);
    final y1 = (bounds.top + bounds.height).toInt().clamp(0, pixels.height);

    final values = <double>[];
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final raw = _rawAt(pixels, y * pixels.width + x);
        values.add(
          unit == DicomMeasurementUnit.modalityValue
              ? pixels.transform.toModalityValue(raw)
              : raw,
        );
      }
    }
    return RoiStatistics.fromValues(values);
  }

  double _rawAt(final DicomPixelData pixels, final int index) {
    return switch (pixels) {
      DicomInt16PixelData(:final buffer) => buffer[index].toDouble(),
      DicomUint8PixelData(:final buffer) => buffer[index].toDouble(),
      DicomUint16PixelData(:final buffer) => buffer[index].toDouble(),
      DicomFloat32PixelData(:final buffer) => buffer[index].toDouble(),
      DicomRgbPixelData(:final buffer) =>
        (buffer[index * 3] + buffer[index * 3 + 1] + buffer[index * 3 + 2]) /
            3.0,
    };
  }
}

/// Descriptive statistics over an ROI.
final class RoiStatistics {
  /// Creates statistics from precomputed aggregate values.
  const RoiStatistics({
    required this.pixelCount,
    required this.min,
    required this.max,
    required this.mean,
    required this.stdDev,
    required this.median,
  });

  /// Computes statistics from raw [values].
  factory RoiStatistics.fromValues(final List<double> values) {
    if (values.isEmpty) {
      return const RoiStatistics(
        pixelCount: 0,
        min: 0,
        max: 0,
        mean: 0,
        stdDev: 0,
        median: 0,
      );
    }
    final sorted = List<double>.of(values)..sort();
    final mean = values.reduce((final a, final b) => a + b) / values.length;
    var variance = 0.0;
    for (final v in values) {
      variance += (v - mean) * (v - mean);
    }
    variance /= values.length;
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2.0;
    return RoiStatistics(
      pixelCount: values.length,
      min: sorted.first,
      max: sorted.last,
      mean: mean,
      stdDev: math.sqrt(variance),
      median: median,
    );
  }

  /// Number of pixels included in the statistics.
  final int pixelCount;

  /// Minimum sampled value.
  final double min;

  /// Maximum sampled value.
  final double max;

  /// Arithmetic mean of sampled values.
  final double mean;

  /// Population standard deviation of sampled values.
  final double stdDev;

  /// Median of sampled values.
  final double median;
}
