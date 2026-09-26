import '../../domain/dicom_frame.dart';
import '../../domain/dicom_pixel_data.dart';

/// Decoder port — implementations (`RustDicomDecoder`, `WasmDicomDecoder`,
/// `MockDicomDecoder`) hide behind this interface.
abstract interface class DicomDecoder {
  Future<DicomPixelData> decode(
    final DicomFrame frame, {
    final DicomDecodeOptions options = const DicomDecodeOptions(),
  });
}
