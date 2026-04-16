import '../../rust/api/core/config/dicom_config.dart';
import '../../rust/api/core/models/dicom_frame_result.dart';
import '../../rust/api/init.dart';

/// Abstract interface for DICOM loading strategy.
/// Allows for future implementations like NetworkDicomLoader, etc.
abstract class IDicomLoader {
  Future<DicomFrameResult> load(final String source, {final DicomConfig? config});
}

/// Local file implementation of DICOM loader.
class FileDicomLoader implements IDicomLoader {
  @override
  Future<DicomFrameResult> load(final String filePath, {final DicomConfig? config}) async {
    final finalConfig = config ?? await DicomConfig.default_();
    return loadDicom(path: filePath, config: finalConfig);
  }
}

/// Service that orchestrates DICOM operations.
class DicomService {

  DicomService({final IDicomLoader? loader}) : _loader = loader ?? FileDicomLoader();
  final IDicomLoader _loader;

  Future<DicomFrameResult> loadFrame(final String path, {final DicomConfig? config}) {
    return _loader.load(path, config: config);
  }
}
