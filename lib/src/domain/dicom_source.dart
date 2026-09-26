import 'dart:typed_data';

/// Input API — every acquisition path ends at the same pipeline.
///
/// The parser / decoder never see files, bytes, HTTP, or DIMSE directly;
/// infrastructure adapters translate a [DicomSource] into one domain model.
/// Future sources (`dicomWeb`, `pacs`) extend this sealed hierarchy without
/// changing the parser contract.
sealed class DicomSource {
  const DicomSource();

  /// Single file on disk (mobile / desktop).
  const factory DicomSource.file(String path) = DicomFileSource;

  /// Single file in memory (Web, PACS download, cache).
  const factory DicomSource.bytes(Uint8List bytes) = DicomBytesSource;

  /// Explicit file list forming a series / volume.
  const factory DicomSource.files(List<String> paths) = DicomFilesSource;

  /// In-memory file list forming a series / volume.
  const factory DicomSource.bytesList(List<Uint8List> files) =
      DicomBytesListSource;
}

/// Single file on disk.
final class DicomFileSource extends DicomSource {
  const DicomFileSource(this.path);
  final String path;
}

/// Single file in memory.
final class DicomBytesSource extends DicomSource {
  const DicomBytesSource(this.bytes);
  final Uint8List bytes;
}

/// Explicit file list forming a series / volume.
final class DicomFilesSource extends DicomSource {
  const DicomFilesSource(this.paths);
  final List<String> paths;
}

/// In-memory file list forming a series / volume.
final class DicomBytesListSource extends DicomSource {
  const DicomBytesListSource(this.files);
  final List<Uint8List> files;
}
