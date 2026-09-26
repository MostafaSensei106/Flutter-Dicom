import '../../application/ports/dicom_decoder.dart';
import '../../domain/dicom_frame.dart';
import '../../domain/dicom_pixel_data.dart';
import '../../errors/dicom_exception.dart';

/// Rust-backed decoder.
///
/// Frames produced by [DicomFrameProvider.get] already carry their pixels,
/// so `decode` returns them directly. Frames constructed by hand (tests,
/// custom providers) without pixels cannot be decoded — fetch them through
/// a provider instead.
final class RustDicomDecoder implements DicomDecoder {
  /// Creates a Rust-backed decoder.
  const RustDicomDecoder();

  @override
  Future<DicomPixelData> decode(
    final DicomFrame frame, {
    final DicomDecodeOptions options = const DicomDecodeOptions(),
  }) async {
    final pixels = frame.pixelData;
    if (pixels == null) {
      throw DicomConfigurationException(
        'Frame ${frame.index} carries no pixels; '
        'obtain frames via DicomFrameProvider.get()',
      );
    }
    return pixels;
  }
}
