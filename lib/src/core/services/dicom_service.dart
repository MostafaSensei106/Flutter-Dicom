import 'package:flutter_dicom/src/rust/api/core/config/dicom_config.dart';
import 'package:flutter_dicom/src/rust/api/core/models/dicom_frame_result.dart';
import 'package:flutter_dicom/src/rust/api/init.dart';

/// Abstract interface for DICOM loading strategy.
/// Allows for future implementations like NetworkDicomLoader, etc.
abstract class IDicomLoader {
  Future<DicomFrameResult> load(String source, {DicomConfig? config});
}

/// Local file implementation of DICOM loader.
class FileDicomLoader implements IDicomLoader {
  @override
  Future<DicomFrameResult> load(String filePath, {DicomConfig? config}) async {
    final finalConfig = config ?? await DicomConfig.default_();
    return await loadDicom(path: filePath, config: finalConfig);
  }
}

/// Service that orchestrates DICOM operations.
class DicomService {
  final IDicomLoader _loader;

  DicomService({IDicomLoader? loader}) : _loader = loader ?? FileDicomLoader();

  Future<DicomFrameResult> loadFrame(String path, {DicomConfig? config}) {
    return _loader.load(path, config: config);
  }
}
