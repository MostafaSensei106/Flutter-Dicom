/// Base exception for all DICOM-related errors in the SDK.
abstract class DicomException implements Exception {

  const DicomException(this.message, [this.originalError]);
  final String message;
  final dynamic originalError;

  @override
  String toString() {
    if (originalError != null) {
      return '$runtimeType: $message (Details: $originalError)';
    }
    return '$runtimeType: $message';
  }
}

/// Thrown when the Rust engine fails to parse or process the file.
class DicomProcessingException extends DicomException {
  const DicomProcessingException(super.message, [super.originalError]);
}

/// Thrown when the Fragment Shader fails to load or compile.
class DicomShaderException extends DicomException {
  const DicomShaderException(super.message);
}

/// Thrown when an invalid configuration is passed to the SDK.
class DicomConfigurationException extends DicomException {
  const DicomConfigurationException(super.message);
}
