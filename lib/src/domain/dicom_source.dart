
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
  const factory DicomSource.file(final String path) = DicomFileSource;

  /// Single file in memory (Web, PACS download, cache).
  const factory DicomSource.bytes(final Uint8List bytes) = DicomBytesSource;

  /// Explicit file list forming a series / volume.
  const factory DicomSource.files(final List<String> paths) = DicomFilesSource;

  /// In-memory file list forming a series / volume.
  const factory DicomSource.bytesList(final List<Uint8List> files) =
      DicomBytesListSource;
}

/// Single file on disk.
final class DicomFileSource extends DicomSource {
  /// Creates a file source for [path].
  const DicomFileSource(this.path);

  /// File path on disk.
  final String path;
}

/// Single file in memory.
final class DicomBytesSource extends DicomSource {
  /// Creates an in-memory source from [bytes].
  const DicomBytesSource(this.bytes);

  /// Raw file bytes.
  final Uint8List bytes;
}

/// Explicit file list forming a series / volume.
final class DicomFilesSource extends DicomSource {
  /// Creates a file-list source from [paths].
  const DicomFilesSource(this.paths);

  /// File paths forming the series.
  final List<String> paths;
}

/// In-memory file list forming a series / volume.
final class DicomBytesListSource extends DicomSource {
  /// Creates an in-memory file-list source from [files].
  const DicomBytesListSource(this.files);

  /// Raw file bytes forming the series.
  final List<Uint8List> files;
}
