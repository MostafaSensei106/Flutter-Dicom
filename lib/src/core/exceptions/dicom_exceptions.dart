/// Base exception for all DICOM-related errors in the SDK.
///
/// All specialized exceptions in the Flutter-Dicom package inherit from this class,
/// allowing you to catch all medical imaging errors in a single block.
abstract class DicomException implements Exception {
  /// Creates a [DicomException].
  const DicomException(this.message, [this.originalError]);

  /// A human-readable message explaining what went wrong.
  final String message;

  /// The underlying error (e.g., a FileSystemException or Rust panic) if available.
  final dynamic originalError;

  @override
  String toString() {
    if (originalError != null) {
      return '$runtimeType: $message (Details: $originalError)';
    }
    return '$runtimeType: $message';
  }
}

/// Thrown when the high-performance Rust engine fails to parse or process the file.
///
/// Common causes include:
/// * Corrupted .dcm file.
/// * Unsupported DICOM transfer syntax.
/// * Memory allocation failures during large volume parsing.
class DicomProcessingException extends DicomException {
  const DicomProcessingException(super.message, [super.originalError]);
}

/// Thrown when the GPU Fragment Shader fails to load or compile.
///
/// This usually indicates an issue with the Flutter assets configuration
/// or an incompatible graphics driver on the target device.
class DicomShaderException extends DicomException {
  const DicomShaderException(super.message);
}

/// Thrown when an invalid configuration is passed to the SDK.
class DicomConfigurationException extends DicomException {
  const DicomConfigurationException(super.message);
}
