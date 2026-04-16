import '../../rust/api/core/config/dicom_config.dart';
import '../../rust/api/core/models/dicom_frame_result.dart';
import '../../rust/api/init.dart';

/// An abstract interface defining how DICOM files are loaded.
///
/// By using this interface, the SDK allows for pluggable loading strategies.
/// For example, you could implement a `NetworkDicomLoader` to stream bytes
/// directly from a PACS server without saving to a local file first.
abstract class IDicomLoader {
  /// Loads a DICOM object from the specified [source].
  Future<DicomFrameResult> load(final String source,
      {final DicomConfig? config});
}

/// The default implementation for loading DICOM files from the local file system.
class FileDicomLoader implements IDicomLoader {
  /// Loads a .dcm file using the high-performance Rust bridge.
  @override
  Future<DicomFrameResult> load(final String filePath,
      {final DicomConfig? config}) async {
    final finalConfig = config ?? await DicomConfig.default_();
    return loadDicom(path: filePath, config: finalConfig);
  }
}

/// A domain service that orchestrates DICOM operations.
///
/// This class serves as a bridge between the [DicomController] (State Management)
/// and the [IDicomLoader] (Data Access).
class DicomService {
  /// Creates a [DicomService] with a specific loader.
  ///
  /// Defaults to [FileDicomLoader] if no loader is provided.
  DicomService({final IDicomLoader? loader})
      : _loader = loader ?? FileDicomLoader();
  final IDicomLoader _loader;

  /// Requests a processed DICOM frame from the underlying loader.
  Future<DicomFrameResult> loadFrame(final String path,
      {final DicomConfig? config}) {
    return _loader.load(path, config: config);
  }
}
