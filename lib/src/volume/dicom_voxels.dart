import 'dart:typed_data';

import '../domain/dicom_pixel_data.dart';
import 'dicom_volume.dart';

/// Voxel volume: a [DicomVolume] meta plus its decoded stored values.
///
/// Voxels are x-fastest (`index = (z * height + y) * width + x`) so axial
/// slices are contiguous. Values are *stored* pixels; [transform] maps them
/// to modality values (HU for CT) at sampling time.
final class DicomVoxelVolume {
  /// Creates a voxel volume with [meta] extents and [voxels] samples.
  DicomVoxelVolume({
    required this.meta,
    required this.voxels,
    this.transform = const DicomPixelTransform(),
  }) : assert(
          voxels.length == meta.width * meta.height * meta.depth,
          'voxel count must match volume extents',
        );

  /// Assembles a voxel volume from decoded [slices] in display order.
  ///
  /// Every slice must share [meta] in-plane extents; pass
  /// `DicomVolume.fromSeries(...)` output as [meta] and the decoded frames
  /// (`provider.get(i)`) as [slices].
  static DicomVoxelVolume assemble({
    required final DicomVolume meta,
    required final List<DicomPixelData> slices,
  }) {
    if (slices.length != meta.depth) {
      throw ArgumentError(
        'Expected ${meta.depth} slices, got ${slices.length}',
      );
    }
    final transform = slices.isNotEmpty
        ? slices.first.transform
        : const DicomPixelTransform();
    final voxels = Int16List(meta.width * meta.height * meta.depth);
    for (var z = 0; z < meta.depth; z++) {
      final slice = slices[z];
      if (slice.width != meta.width || slice.height != meta.height) {
        throw ArgumentError(
          'Slice $z is ${slice.width}x${slice.height}, '
          'expected ${meta.width}x${meta.height}',
        );
      }
      voxels.setRange(
        z * meta.width * meta.height,
        (z + 1) * meta.width * meta.height,
        _storedInt16(slice),
      );
    }
    return DicomVoxelVolume(
      meta: meta,
      voxels: voxels,
      transform: transform,
    );
  }

  /// Volume extents + patient-space geometry.
  final DicomVolume meta;

  /// Stored voxel values in x-fastest order.
  final Int16List voxels;

  /// Stored-to-modality value transform shared by the slices.
  final DicomPixelTransform transform;

  /// Voxel width.
  int get width => meta.width;

  /// Voxel height.
  int get height => meta.height;

  /// Voxel depth.
  int get depth => meta.depth;

  /// Stored value at ([x], [y], [z]) with edge clamping.
  int at(final int x, final int y, final int z) {
    final cx = x.clamp(0, width - 1);
    final cy = y.clamp(0, height - 1);
    final cz = z.clamp(0, depth - 1);
    return voxels[(cz * height + cy) * width + cx];
  }

  /// Modality value at ([x], [y], [z]).
  double modalityAt(final int x, final int y, final int z) =>
      transform.toModalityValue(at(x, y, z).toDouble());

  /// Converts any decoded slice to stored 16-bit samples.
  ///
  /// Same semantics as the GPU upload path: unsigned 16-bit keeps its
  /// offset-binary form, unsigned 8-bit stays native, RGB reduces to
  /// luminance, float32 quantizes across its own range.
  static Int16List _storedInt16(final DicomPixelData pixels) {
    final count = pixels.width * pixels.height;
    final out = Int16List(count);
    switch (pixels) {
      case DicomInt16PixelData(:final buffer):
        out.setRange(0, count, buffer);
      case DicomUint8PixelData(:final buffer):
        for (var i = 0; i < count; i++) {
          out[i] = buffer[i];
        }
      case DicomUint16PixelData(:final buffer):
        for (var i = 0; i < count; i++) {
          out[i] = (buffer[i] - 32768).clamp(-32768, 32767);
        }
      case DicomRgbPixelData(:final buffer):
        for (var i = 0; i < count; i++) {
          out[i] = (0.299 * buffer[i * 3] +
                  0.587 * buffer[i * 3 + 1] +
                  0.114 * buffer[i * 3 + 2])
              .round();
        }
      case DicomFloat32PixelData(:final buffer):
        var min = double.infinity;
        var max = double.negativeInfinity;
        for (var i = 0; i < count; i++) {
          final v = buffer[i];
          if (v < min) min = v;
          if (v > max) max = v;
        }
        final range = (max - min) <= 0 ? 1.0 : (max - min);
        for (var i = 0; i < count; i++) {
          out[i] = (((buffer[i] - min) / range) * 65535 - 32768)
              .round()
              .clamp(-32768, 32767);
        }
    }
    return out;
  }
}
