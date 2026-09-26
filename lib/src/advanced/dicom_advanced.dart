import 'dart:typed_data';

import '../domain/dicom_pixel_data.dart';
import '../volume/dicom_volume.dart';

/// Binary segmentation mask.
final class DicomSegmentationMask {
  const DicomSegmentationMask({
    required this.width,
    required this.height,
    required this.data,
  });
  final int width;
  final int height;
  final Uint8List data;
}

/// Segmentation algorithm port — AI is a strategy, not core.
abstract interface class DicomSegmentationAlgorithm {
  Future<DicomSegmentationMask> segment(final DicomPixelData image);
}

/// Multi-modal fusion model.
final class DicomFusion {
  const DicomFusion({
    required this.base,
    required this.overlay,
    required this.registration,
  });
  final DicomVolume base;
  final DicomVolume overlay;
  final DicomRegistration registration;
}

/// Registration result between two volumes.
final class DicomRegistration {
  const DicomRegistration({this.matrix = const []});
  final List<double> matrix;
}

/// Registration strategy port (identity / rigid / affine / deformable).
abstract interface class DicomRegistrationStrategy {
  Future<DicomRegistration> register(final DicomVolume source, final DicomVolume target);
}
