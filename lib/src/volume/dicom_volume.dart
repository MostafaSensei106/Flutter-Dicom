import 'dart:typed_data';

import '../domain/dicom_geometry.dart';
import '../domain/dicom_pixel_data.dart';

/// Reconstruction plane for MPR sampling.
enum DicomPlane {
  axial,
  sagittal,
  coronal,
  oblique,
}

/// Interpolation used during reconstruction / projection.
enum DicomInterpolation {
  nearest,
  trilinear,
}

/// Projection flavor sharing one pipeline.
enum DicomProjectionType {
  maximum,
  minimum,
}

/// Coordinate-aware 3D representation built from a series.
final class DicomVolume {
  const DicomVolume({
    required this.width,
    required this.height,
    required this.depth,
    required this.geometry,
  });

  final int width;
  final int height;
  final int depth;
  final DicomVolumeGeometry geometry;

  Future<DicomVolumeSlice> sample(final DicomPlane plane, final double position) async =>
      DicomVolumeSlice(plane: plane, position: position);
}

/// A resampled slice through the volume.
final class DicomVolumeSlice {
  const DicomVolumeSlice({required this.plane, required this.position});
  final DicomPlane plane;
  final double position;
}

/// Volume extents in patient coordinates.
final class DicomVolumeGeometry {
  const DicomVolumeGeometry({required this.origin, required this.spacing});
  final DicomPosition origin;
  final List<double> spacing;
}

/// MPR reconstruction strategy (nearest / trilinear / …).
abstract interface class DicomReconstructionStrategy {
  Future<DicomPixelData> reconstruct(
    final DicomVolume volume,
    final DicomPlane plane,
    final double position,
  );
}

/// MIP / MinIP projection strategy — same pipeline, both flavors.
abstract interface class DicomProjectionStrategy {
  Future<DicomPixelData> project(
    final DicomVolume volume,
    final DicomProjectionOptions options,
  );
}

/// Projection tuning.
final class DicomProjectionOptions {
  const DicomProjectionOptions({
    this.type = DicomProjectionType.maximum,
    this.interpolation = DicomInterpolation.trilinear,
  });

  final DicomProjectionType type;
  final DicomInterpolation interpolation;
}

/// MPR controller (plane navigation over a volume).
abstract interface class DicomMprController {
  DicomPlane get plane;
  double get position;
  Future<void> setPlane(final DicomPlane plane);
  Future<void> setPosition(final double position);
  void dispose();
}

/// Raw volume bytes for software fallbacks (typed per pixel format).
final class DicomVolumeBytes {
  const DicomVolumeBytes(this.bytes);
  final Uint8List bytes;
}
