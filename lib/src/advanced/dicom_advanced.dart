import 'dart:typed_data';

import '../domain/dicom_pixel_data.dart';
import '../volume/dicom_volume.dart';

/// Binary segmentation mask.
final class DicomSegmentationMask {
  /// Creates a [width] x [height] mask from binary [data].
  const DicomSegmentationMask({
    required this.width,
    required this.height,
    required this.data,
  });

  /// Mask width in pixels.
  final int width;

  /// Mask height in pixels.
  final int height;

  /// Row-major binary mask bytes.
  final Uint8List data;
}

/// Segmentation algorithm port — AI is a strategy, not core.
abstract interface class DicomSegmentationAlgorithm {
  /// Segments [image] and returns the binary mask.
  Future<DicomSegmentationMask> segment(final DicomPixelData image);
}

/// Multi-modal fusion model.
final class DicomFusion {
  /// Creates a fusion of [base] and [overlay] volumes with [registration].
  const DicomFusion({
    required this.base,
    required this.overlay,
    required this.registration,
  });

  /// Reference volume that the overlay aligns to.
  final DicomVolume base;

  /// Secondary volume aligned onto the base.
  final DicomVolume overlay;

  /// Registration mapping the overlay onto the base.
  final DicomRegistration registration;
}

/// Registration result between two volumes.
final class DicomRegistration {
  /// Creates a registration with a row-major [matrix] transform.
  const DicomRegistration({this.matrix = const []});

  /// Row-major transform matrix mapping source to target.
  final List<double> matrix;
}

/// Registration strategy port (identity / rigid / affine / deformable).
abstract interface class DicomRegistrationStrategy {
  /// Registers [source] onto [target] and returns the transform.
  Future<DicomRegistration> register(final DicomVolume source, final DicomVolume target);
}
