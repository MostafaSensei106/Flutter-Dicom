import 'dart:typed_data';

import '../domain/dicom_geometry.dart';
import '../domain/dicom_pixel_data.dart';

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

/// Coordinate-aware 3D representation built from a series.
final class DicomVolume {
  /// Creates a volume with voxel extents and patient-space [geometry].
  const DicomVolume({
    required this.width,
    required this.height,
    required this.depth,
    required this.geometry,
  });

  /// Voxel count along the x axis.
  final int width;

  /// Voxel count along the y axis.
  final int height;

  /// Voxel count along the z axis.
  final int depth;

  /// Patient-space geometry of the volume.
  final DicomVolumeGeometry geometry;

  /// Samples a resampled [plane] slice at [position].
  Future<DicomVolumeSlice> sample(final DicomPlane plane, final double position) async =>
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

/// MPR reconstruction strategy (nearest / trilinear / …).
abstract interface class DicomReconstructionStrategy {
  /// Reconstructs a [plane] slice at [position] from [volume].
  Future<DicomPixelData> reconstruct(
    final DicomVolume volume,
    final DicomPlane plane,
    final double position,
  );
}

/// MIP / MinIP projection strategy — same pipeline, both flavors.
abstract interface class DicomProjectionStrategy {
  /// Projects [volume] using the given [options].
  Future<DicomPixelData> project(
    final DicomVolume volume,
    final DicomProjectionOptions options,
  );
}

/// Projection tuning.
final class DicomProjectionOptions {
  /// Creates projection options with a [type] and [interpolation].
  const DicomProjectionOptions({
    this.type = DicomProjectionType.maximum,
    this.interpolation = DicomInterpolation.trilinear,
  });

  /// Projection flavor to apply.
  final DicomProjectionType type;

  /// Interpolation used during projection.
  final DicomInterpolation interpolation;
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
