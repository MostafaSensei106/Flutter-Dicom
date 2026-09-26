import 'dart:typed_data';

import '../domain/dicom_geometry.dart';
import '../series/dicom_series.dart';

/// Reconstruction plane for MPR sampling.
enum DicomPlane {
  /// Transverse plane (viewed from below/above).
  axial,

  /// Side plane dividing left from right.
  sagittal,

  /// Frontal plane dividing front from back.
  coronal,

  /// Arbitrary plane not aligned to the major axes.
  oblique,
}

/// Interpolation used during reconstruction / projection.
enum DicomInterpolation {
  /// Nearest-voxel sampling without blending.
  nearest,

  /// Trilinear blending of the eight nearest voxels.
  trilinear,
}

/// Projection flavor sharing one pipeline.
enum DicomProjectionType {
  /// Maximum intensity projection.
  maximum,

  /// Minimum intensity projection.
  minimum,
}

/// Axis a projection collapses.
enum DicomProjectionAxis {
  /// Collapse x: output is (height × depth), viewed from the side.
  x,

  /// Collapse y: output is (width × depth), viewed from the front.
  y,

  /// Collapse z: output is (width × height), viewed from above.
  z,
}

/// Projection tuning.
final class DicomProjectionOptions {
  /// Creates projection options with a [type], [axis], and [interpolation].
  const DicomProjectionOptions({
    this.type = DicomProjectionType.maximum,
    this.axis = DicomProjectionAxis.z,
    this.interpolation = DicomInterpolation.nearest,
  });

  /// Projection flavor to apply.
  final DicomProjectionType type;

  /// Axis to collapse.
  final DicomProjectionAxis axis;

  /// Interpolation used during projection (nearest today).
  final DicomInterpolation interpolation;
}

/// Coordinate-aware 3D representation built from a series.
final class DicomVolume {
  /// Creates a volume with voxel extents and patient-space [geometry].
  const DicomVolume({
    required this.width,
    required this.height,
    required this.depth,
    required this.geometry,
  });

  /// Builds a volume from a spatially sorted [series].
  ///
  /// In-plane spacing comes from the series pixel spacing (1.0 mm fallback);
  /// through-plane spacing is the median slice-position gap (1.0 fallback).
  /// Origin is the first slice position (patient mm) or the zero point.
  factory DicomVolume.fromSeries(
    final DicomSeries series, {
    required final int width,
    required final int height,
  }) {
    final depth = series.sliceCount;
    final inPlane = series.geometry.pixelSpacing;
    final positions = series.geometry.slicePositions;
    return DicomVolume(
      width: width,
      height: height,
      depth: depth,
      geometry: DicomVolumeGeometry(
        origin: series.frames.isNotEmpty &&
                series.frames.first.position != null
            ? series.frames.first.position!
            : const DicomPosition(0, 0, 0),
        spacing: [
          inPlane?.column ?? 1.0,
          inPlane?.row ?? 1.0,
          _sliceGap(positions),
        ],
      ),
    );
  }

  /// Median gap between consecutive slice positions (robust to one bad tag).
  static double _sliceGap(final List<double> positions) {
    if (positions.length < 2) return 1.0;
    final gaps = <double>[];
    for (var i = 1; i < positions.length; i++) {
      final gap = (positions[i] - positions[i - 1]).abs();
      if (gap > 0) gaps.add(gap);
    }
    if (gaps.isEmpty) return 1.0;
    gaps.sort();
    return gaps[gaps.length ~/ 2];
  }

  /// Voxel count along the x axis.
  final int width;

  /// Voxel count along the y axis.
  final int height;

  /// Voxel count along the z axis.
  final int depth;

  /// Patient-space geometry of the volume.
  final DicomVolumeGeometry geometry;

  /// Voxel extents as `[width, height, depth]`.
  List<int> get dimensions => [width, height, depth];

  /// Voxel spacing in mm as `[x, y, z]`.
  List<double> get voxelSpacing => geometry.spacing;

  /// Samples a resampled [plane] slice at [position].
  Future<DicomVolumeSlice> sample(
          final DicomPlane plane, final double position) async =>
      DicomVolumeSlice(plane: plane, position: position);
}

/// A resampled slice through the volume.
final class DicomVolumeSlice {
  /// Creates a resampled slice on [plane] at [position].
  const DicomVolumeSlice({required this.plane, required this.position});

  /// Reconstruction plane of the slice.
  final DicomPlane plane;

  /// Position of the slice along the plane normal.
  final double position;
}

/// Volume extents in patient coordinates.
final class DicomVolumeGeometry {
  /// Creates volume geometry with patient-space [origin] and [spacing].
  const DicomVolumeGeometry({required this.origin, required this.spacing});

  /// Patient-space origin of the volume.
  final DicomPosition origin;

  /// Voxel spacing along each axis.
  final List<double> spacing;
}

/// MPR controller (plane navigation over a volume).
abstract interface class DicomMprController {
  /// Currently selected reconstruction plane.
  DicomPlane get plane;

  /// Current position along the plane normal.
  double get position;

  /// Selects a new reconstruction [plane].
  Future<void> setPlane(final DicomPlane plane);

  /// Moves to a new [position] along the plane normal.
  Future<void> setPosition(final double position);

  /// Releases resources held by the controller.
  void dispose();
}

/// Raw volume bytes for software fallbacks (typed per pixel format).
final class DicomVolumeBytes {
  /// Wraps raw volume [bytes] for software fallbacks.
  const DicomVolumeBytes(this.bytes);

  /// Raw volume bytes in pixel-format order.
  final Uint8List bytes;
}
