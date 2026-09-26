import 'dart:async';
import 'dart:typed_data';

import '../domain/dicom_pixel_data.dart';
import 'dicom_volume.dart';
import 'dicom_voxels.dart';

/// MPR reconstruction strategy (nearest / trilinear / …).
///
/// Axis mapping (voxel indices, zero-based):
/// * axial → output (width × height), `out(x, y) = V(x, y, position)`
/// * coronal → output (width × depth), `out(x, z) = V(x, position, z)`
/// * sagittal → output (height × depth), `out(y, z) = V(position, y, z)`
///
/// [position] is a voxel index along the plane normal and is clamped to
/// the volume. Oblique planes throw [UnimplementedError].
abstract interface class DicomReconstructionStrategy {
  /// Reconstructs a [plane] slice at [position] from [volume].
  Future<DicomPixelData> reconstruct(
    final DicomVoxelVolume volume,
    final DicomPlane plane,
    final double position,
  );
}

/// Nearest-voxel MPR sampling without blending.
final class NearestReconstruction implements DicomReconstructionStrategy {
  /// Creates nearest-voxel reconstruction.
  const NearestReconstruction();

  @override
  Future<DicomPixelData> reconstruct(
    final DicomVoxelVolume volume,
    final DicomPlane plane,
    final double position,
  ) async {
    return switch (plane) {
      DicomPlane.axial => DicomInt16PixelData(
          buffer: _axial(volume, position.round()),
          width: volume.width,
          height: volume.height,
          transform: volume.transform,
        ),
      DicomPlane.coronal => DicomInt16PixelData(
          buffer: _coronal(volume, position.round()),
          width: volume.width,
          height: volume.depth,
          transform: volume.transform,
        ),
      DicomPlane.sagittal => DicomInt16PixelData(
          buffer: _sagittal(volume, position.round()),
          width: volume.height,
          height: volume.depth,
          transform: volume.transform,
        ),
      DicomPlane.oblique => throw UnimplementedError(
          'Oblique MPR needs an oriented resampling grid (M5 scope: '
          'axial/coronal/sagittal only)',
        ),
    };
  }

  /// Axial slice at integer [z] (x-fastest copy of one z row-block).
  static Int16List _axial(final DicomVoxelVolume v, final int z) {
    final cz = z.clamp(0, v.depth - 1);
    final out = Int16List(v.width * v.height);
    for (var y = 0; y < v.height; y++) {
      for (var x = 0; x < v.width; x++) {
        out[y * v.width + x] = v.at(x, y, cz);
      }
    }
    return out;
  }

  /// Coronal slice at integer [y].
  static Int16List _coronal(final DicomVoxelVolume v, final int y) {
    final cy = y.clamp(0, v.height - 1);
    final out = Int16List(v.width * v.depth);
    for (var z = 0; z < v.depth; z++) {
      for (var x = 0; x < v.width; x++) {
        out[z * v.width + x] = v.at(x, cy, z);
      }
    }
    return out;
  }

  /// Sagittal slice at integer [x].
  static Int16List _sagittal(final DicomVoxelVolume v, final int x) {
    final cx = x.clamp(0, v.width - 1);
    final out = Int16List(v.height * v.depth);
    for (var z = 0; z < v.depth; z++) {
      for (var y = 0; y < v.height; y++) {
        out[z * v.height + y] = v.at(cx, y, z);
      }
    }
    return out;
  }
}

/// Trilinear MPR sampling blending the eight nearest voxels.
final class TrilinearReconstruction implements DicomReconstructionStrategy {
  /// Creates trilinear reconstruction.
  const TrilinearReconstruction();

  @override
  Future<DicomPixelData> reconstruct(
    final DicomVoxelVolume volume,
    final DicomPlane plane,
    final double position,
  ) async {
    return switch (plane) {
      DicomPlane.axial => DicomInt16PixelData(
          buffer: _plane(
            volume,
            volume.width,
            volume.height,
            (final x, final y) => _sample(volume, x, y, position),
          ),
          width: volume.width,
          height: volume.height,
          transform: volume.transform,
        ),
      DicomPlane.coronal => DicomInt16PixelData(
          buffer: _plane(
            volume,
            volume.width,
            volume.depth,
            (final x, final z) => _sample(volume, x, position, z),
          ),
          width: volume.width,
          height: volume.depth,
          transform: volume.transform,
        ),
      DicomPlane.sagittal => DicomInt16PixelData(
          buffer: _plane(
            volume,
            volume.height,
            volume.depth,
            (final y, final z) => _sample(volume, position, y, z),
          ),
          width: volume.height,
          height: volume.depth,
          transform: volume.transform,
        ),
      DicomPlane.oblique => throw UnimplementedError(
          'Oblique MPR needs an oriented resampling grid (M5 scope: '
          'axial/coronal/sagittal only)',
        ),
    };
  }

  static Int16List _plane(
    final DicomVoxelVolume volume,
    final int w,
    final int h,
    final double Function(double a, double b) sample,
  ) {
    final out = Int16List(w * h);
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        out[j * w + i] =
            sample(i.toDouble(), j.toDouble()).round().clamp(-32768, 32767);
      }
    }
    return out;
  }

  /// Trilinear sample at fractional voxel coordinates (edge-clamped).
  static double _sample(
    final DicomVoxelVolume v,
    final double x,
    final double y,
    final double z,
  ) {
    final x0 = x.floor().clamp(0, v.width - 1);
    final y0 = y.floor().clamp(0, v.height - 1);
    final z0 = z.floor().clamp(0, v.depth - 1);
    final x1 = (x0 + 1).clamp(0, v.width - 1);
    final y1 = (y0 + 1).clamp(0, v.height - 1);
    final z1 = (z0 + 1).clamp(0, v.depth - 1);
    final fx = (x - x0).clamp(0.0, 1.0);
    final fy = (y - y0).clamp(0.0, 1.0);
    final fz = (z - z0).clamp(0.0, 1.0);
    double lerp(final double a, final double b, final double t) =>
        a + (b - a) * t;
    final c000 = v.at(x0, y0, z0).toDouble();
    final c100 = v.at(x1, y0, z0).toDouble();
    final c010 = v.at(x0, y1, z0).toDouble();
    final c110 = v.at(x1, y1, z0).toDouble();
    final c001 = v.at(x0, y0, z1).toDouble();
    final c101 = v.at(x1, y0, z1).toDouble();
    final c011 = v.at(x0, y1, z1).toDouble();
    final c111 = v.at(x1, y1, z1).toDouble();
    return lerp(
      lerp(
        lerp(c000, c100, fx),
        lerp(c010, c110, fx),
        fy,
      ),
      lerp(
        lerp(c001, c101, fx),
        lerp(c011, c111, fx),
        fy,
      ),
      fz,
    );
  }
}

/// Voxel-space crosshair point shared by the three MPR views.
final class DicomMprPoint {
  /// Creates a crosshair point in voxel indices (may be fractional).
  const DicomMprPoint(this.x, this.y, this.z);

  /// Position along the x axis.
  final double x;

  /// Position along the y axis.
  final double y;

  /// Position along the z axis.
  final double z;
}

/// Mediator syncing the axial / coronal / sagittal crosshairs.
///
/// Views never talk to each other: one [setPoint] updates all three at the
/// same moment, and every view subscribes to [points].
abstract interface class DicomMprCoordinator {
  /// Current crosshair point in voxel indices.
  DicomMprPoint get point;

  /// Broadcast of crosshair moves.
  Stream<DicomMprPoint> get points;

  /// Moves the crosshair, notifying axial + coronal + sagittal together.
  void setPoint(final DicomMprPoint point);

  /// Releases resources held by the coordinator.
  void dispose();
}

/// Default broadcast crosshair coordinator.
final class DefaultDicomMprCoordinator implements DicomMprCoordinator {
  /// Creates a coordinator at [initial] (volume center by default).
  DefaultDicomMprCoordinator({
    this.initial = const DicomMprPoint(0, 0, 0),
  }) : _point = initial;

  /// Initial crosshair point.
  final DicomMprPoint initial;

  final StreamController<DicomMprPoint> _events =
      StreamController<DicomMprPoint>.broadcast();
  DicomMprPoint _point;

  @override
  DicomMprPoint get point => _point;

  @override
  Stream<DicomMprPoint> get points => _events.stream;

  @override
  void setPoint(final DicomMprPoint point) {
    _point = point;
    if (!_events.isClosed) _events.add(point);
  }

  @override
  void dispose() {
    unawaited(_events.close());
  }
}

/// Default MPR controller navigating one reconstruction plane.
final class DefaultDicomMprController implements DicomMprController {
  /// Creates a controller on [plane] at [position].
  DefaultDicomMprController({
    final DicomPlane plane = DicomPlane.axial,
    final double position = 0,
  })  : _plane = plane,
        _position = position;

  DicomPlane _plane;
  double _position;

  @override
  DicomPlane get plane => _plane;

  @override
  double get position => _position;

  @override
  Future<void> setPlane(final DicomPlane plane) async {
    _plane = plane;
  }

  @override
  Future<void> setPosition(final double position) async {
    _position = position;
  }

  @override
  void dispose() {}
}
