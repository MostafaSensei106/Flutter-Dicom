import '../domain/dicom_geometry.dart';
import '../domain/dicom_pixel_data.dart';

/// Probe result at one image point — works for mouse, touch, stylus,
/// network-driven, or test inputs alike.
final class DicomProbeResult {
  /// Creates a probe result at [coordinate] with raw and modality values.
  const DicomProbeResult({
    required this.coordinate,
    required this.rawValue,
    required this.modalityValue,
    this.hu,
    this.patientPosition,
  });

  /// Image-pixel coordinate that was probed.
  final DicomPoint coordinate;

  /// Raw stored pixel value before modality transform.
  final double rawValue;

  /// Value after applying the modality (rescale) transform.
  final double modalityValue;

  /// Hounsfield units, when CT semantics apply.
  final double? hu;

  /// Patient coordinates in mm, when geometry is known.
  final List<double>? patientPosition;
}

/// Probe port — an overlay displays the result; it never computes HU itself.
abstract interface class DicomProbe {
  /// Samples [pixels] at [imagePoint] and returns the probe result.
  DicomProbeResult probe(
      final DicomPixelData pixels, final DicomPoint imagePoint);
}

/// Default probe using the shared [DicomPixelTransform].
final class ModalityProbe implements DicomProbe {
  /// Creates a modality probe, optionally reporting HU.
  const ModalityProbe({this.reportHu = true});

  /// Whether to populate [DicomProbeResult.hu] (CT semantics).
  final bool reportHu;

  @override
  DicomProbeResult probe(
      final DicomPixelData pixels, final DicomPoint imagePoint) {
    final x = imagePoint.x.toInt().clamp(0, pixels.width - 1);
    final y = imagePoint.y.toInt().clamp(0, pixels.height - 1);
    final index = y * pixels.width + x;
    double raw;
    switch (pixels) {
      case DicomInt16PixelData(:final buffer):
        raw = buffer[index].toDouble();
      case DicomUint8PixelData(:final buffer):
        raw = buffer[index].toDouble();
      case DicomUint16PixelData(:final buffer):
        raw = buffer[index].toDouble();
      case DicomFloat32PixelData(:final buffer):
        raw = buffer[index].toDouble();
      case DicomRgbPixelData(:final buffer):
        raw = (buffer[index * 3] +
                buffer[index * 3 + 1] +
                buffer[index * 3 + 2]) /
            3.0;
    }
    final modality = pixels.transform.toModalityValue(raw);
    return DicomProbeResult(
      coordinate: DicomPoint(x.toDouble(), y.toDouble()),
      rawValue: raw,
      modalityValue: modality,
      hu: reportHu ? modality : null,
    );
  }
}
