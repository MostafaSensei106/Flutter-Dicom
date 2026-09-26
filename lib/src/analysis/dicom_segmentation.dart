import 'dart:typed_data';

import '../advanced/dicom_advanced.dart';
import '../domain/dicom_geometry.dart';
import '../domain/dicom_pixel_data.dart';
import 'dicom_roi.dart';

/// Threshold segmentation: modality values inside `[lower, upper]`.
///
/// The workhorse for CT (bone/lung windows) and PET (SUV cutoffs) before
/// any AI model enters through the same [DicomSegmentationAlgorithm] port.
final class ThresholdSegmentation implements DicomSegmentationAlgorithm {
  /// Creates a threshold segmentation over [lower]..[upper].
  const ThresholdSegmentation({
    required this.lower,
    required this.upper,
    this.unit = DicomMeasurementUnit.modalityValue,
  }) : assert(lower <= upper, 'threshold lower must not exceed upper');

  /// Inclusive lower bound.
  final double lower;

  /// Inclusive upper bound.
  final double upper;

  /// Value space the bounds apply to.
  final DicomMeasurementUnit unit;

  @override
  Future<DicomSegmentationMask> segment(
    final DicomPixelData image,
  ) async {
    final data = Uint8List(image.width * image.height);
    for (var i = 0; i < data.length; i++) {
      final v = unit == DicomMeasurementUnit.modalityValue
          ? image.modalityAt(i)
          : _rawAt(image, i);
      data[i] = (v >= lower && v <= upper) ? 1 : 0;
    }
    return DicomSegmentationMask(
      width: image.width,
      height: image.height,
      data: data,
    );
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

/// Brush segmentation: filled circle at [center] with [radius] pixels.
final class BrushSegmentation implements DicomSegmentationAlgorithm {
  /// Creates a brush stroke segmentation.
  const BrushSegmentation({required this.center, required this.radius})
      : assert(radius > 0, 'brush radius must be positive');

  /// Stroke center in image-pixel coordinates.
  final DicomPoint center;

  /// Stroke radius in image pixels.
  final double radius;

  @override
  Future<DicomSegmentationMask> segment(
    final DicomPixelData image,
  ) async {
    final data = Uint8List(image.width * image.height);
    final r2 = radius * radius;
    final x0 = (center.x - radius).floor().clamp(0, image.width - 1);
    final x1 = (center.x + radius).ceil().clamp(0, image.width - 1);
    final y0 = (center.y - radius).floor().clamp(0, image.height - 1);
    final y1 = (center.y + radius).ceil().clamp(0, image.height - 1);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = x + 0.5 - center.x;
        final dy = y + 0.5 - center.y;
        if (dx * dx + dy * dy <= r2) {
          data[y * image.width + x] = 1;
        }
      }
    }
    return DicomSegmentationMask(
      width: image.width,
      height: image.height,
      data: data,
    );
  }
}

/// Flood-fill segmentation: 4-connected region around [seed] within
/// [tolerance] modality units of the seed value.
final class FloodFillSegmentation implements DicomSegmentationAlgorithm {
  /// Creates a flood-fill segmentation from [seed].
  const FloodFillSegmentation({required this.seed, this.tolerance = 0});

  /// Seed point in image-pixel coordinates.
  final DicomPoint seed;

  /// Accepted deviation from the seed modality value.
  final double tolerance;

  @override
  Future<DicomSegmentationMask> segment(
    final DicomPixelData image,
  ) async {
    final data = Uint8List(image.width * image.height);
    final sx = seed.x.toInt().clamp(0, image.width - 1);
    final sy = seed.y.toInt().clamp(0, image.height - 1);
    final target = image.modalityAt(sy * image.width + sx);
    final stack = [sy * image.width + sx];
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      if (data[i] == 1) continue;
      if ((image.modalityAt(i) - target).abs() > tolerance) continue;
      data[i] = 1;
      final x = i % image.width;
      final y = i ~/ image.width;
      if (x > 0) stack.add(i - 1);
      if (x < image.width - 1) stack.add(i + 1);
      if (y > 0) stack.add(i - image.width);
      if (y < image.height - 1) stack.add(i + image.width);
    }
    return DicomSegmentationMask(
      width: image.width,
      height: image.height,
      data: data,
    );
  }
}

/// Descriptive statistics over a segmentation mask.
final class DicomSegmentationStats {
  /// Creates statistics with a voxel count and optional physical area.
  const DicomSegmentationStats({
    required this.voxelCount,
    this.areaMm2,
    this.bounds,
  });

  /// Computes statistics for [mask], deriving area from [spacing] when set.
  static DicomSegmentationStats compute(
    final DicomSegmentationMask mask, {
    final DicomPixelSpacing? spacing,
  }) {
    var count = 0;
    var minX = mask.width;
    var minY = mask.height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        if (mask.data[y * mask.width + x] == 0) continue;
        count++;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
    return DicomSegmentationStats(
      voxelCount: count,
      areaMm2: spacing == null
          ? null
          : count * spacing.row * spacing.column,
      bounds: count == 0
          ? null
          : DicomRect(
              minX.toDouble(),
              minY.toDouble(),
              (maxX - minX + 1).toDouble(),
              (maxY - minY + 1).toDouble(),
            ),
    );
  }

  /// Number of segmented voxels.
  final int voxelCount;

  /// In-plane area in mm², or null without pixel spacing.
  final double? areaMm2;

  /// Bounding box in image pixels, or null for an empty mask.
  final DicomRect? bounds;
}
