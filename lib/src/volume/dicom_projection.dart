import 'dart:typed_data';

import '../domain/dicom_pixel_data.dart';
import 'dicom_volume.dart';
import 'dicom_voxels.dart';

/// MIP / MinIP projection strategy — same pipeline, both flavors.
///
/// Output extents depend on [DicomProjectionOptions.axis]:
/// * z → (width × height), collapsing depth
/// * y → (width × depth), collapsing height
/// * x → (height × depth), collapsing width
abstract interface class DicomProjectionStrategy {
  /// Projects [volume] using the given [options].
  Future<DicomPixelData> project(
    final DicomVoxelVolume volume,
    final DicomProjectionOptions options,
  );
}

/// Maximum intensity projection.
final class MipProjection implements DicomProjectionStrategy {
  /// Creates a maximum intensity projection.
  const MipProjection();

  @override
  Future<DicomPixelData> project(
    final DicomVoxelVolume volume,
    final DicomProjectionOptions options,
  ) async =>
      _collapse(volume, maximum: true, axis: options.axis);
}

/// Minimum intensity projection.
final class MinIpProjection implements DicomProjectionStrategy {
  /// Creates a minimum intensity projection.
  const MinIpProjection();

  @override
  Future<DicomPixelData> project(
    final DicomVoxelVolume volume,
    final DicomProjectionOptions options,
  ) async =>
      _collapse(volume, maximum: false, axis: options.axis);
}

/// Collapses [axis], keeping per-ray extrema as stored values.
DicomInt16PixelData _collapse(
  final DicomVoxelVolume v, {
  required final bool maximum,
  required final DicomProjectionAxis axis,
}) {
  return switch (axis) {
    DicomProjectionAxis.z => DicomInt16PixelData(
        buffer: Int16List.fromList([
          for (var y = 0; y < v.height; y++)
            for (var x = 0; x < v.width; x++)
              _ray((final i) => v.at(x, y, i), v.depth, maximum),
        ]),
        width: v.width,
        height: v.height,
        transform: v.transform,
      ),
    DicomProjectionAxis.y => DicomInt16PixelData(
        buffer: Int16List.fromList([
          for (var z = 0; z < v.depth; z++)
            for (var x = 0; x < v.width; x++)
              _ray((final i) => v.at(x, i, z), v.height, maximum),
        ]),
        width: v.width,
        height: v.depth,
        transform: v.transform,
      ),
    DicomProjectionAxis.x => DicomInt16PixelData(
        buffer: Int16List.fromList([
          for (var z = 0; z < v.depth; z++)
            for (var y = 0; y < v.height; y++)
              _ray((final i) => v.at(i, y, z), v.width, maximum),
        ]),
        width: v.height,
        height: v.depth,
        transform: v.transform,
      ),
  };
}

/// Extremum of one ray of [length] samples.
int _ray(
  final int Function(int i) sample,
  final int length,
  final bool maximum,
) {
  var best = sample(0);
  for (var i = 1; i < length; i++) {
    final s = sample(i);
    if (maximum ? s > best : s < best) best = s;
  }
  return best;
}
