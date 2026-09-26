import '../../domain/dicom_frame.dart';
import '../../domain/dicom_source.dart';
import '../../errors/dicom_exception.dart';
import '../../rust/api/init.dart';
import '../../series/dicom_series.dart';
import 'rust_metadata_mapper.dart';

/// Rust-backed series loader mapping grouped slices onto the domain model.
///
/// Files are grouped by Series Instance UID in Rust; the largest group wins
/// (multi-series directories should be split by callers via QIDO/worklist).
final class RustDicomSeriesLoader implements DicomSeriesLoader {
  /// Creates a Rust-backed series loader.
  const RustDicomSeriesLoader();

  @override
  Future<DicomSeries> load(
    final DicomSource source, {
    final DicomSeriesLoadOptions options = const DicomSeriesLoadOptions(),
  }) async {
    try {
      final paths = switch (source) {
        DicomFilesSource(:final paths) => paths,
        _ => throw const DicomConfigurationException(
            'Series loading needs DicomSource.files',
          ),
      };
      if (paths.isEmpty) {
        throw const DicomConfigurationException('Empty file list');
      }
      final groups = await loadDicomSeriesFromFiles(paths: paths);
      if (groups.isEmpty) {
        throw const DicomProcessingException('No DICOM series found');
      }
      groups.sort(
          (final a, final b) => b.slices.length.compareTo(a.slices.length));
      final group = groups.first;
      final frames = <DicomFrameReference>[];
      final positions = <double>[];
      for (var i = 0; i < group.slices.length; i++) {
        final slice = group.slices[i];
        frames.add(DicomFrameReference(index: i, label: slice.filePath));
        positions.add(slice.metadata.sliceLocation.toDouble());
      }
      final orientation = group.slices.isNotEmpty
          ? RustMetadataMapper.toDomain(
              group.slices.first.metadata,
            ).imageOrientationPatient
          : null;
      return DicomSeries(
        frames: frames,
        geometry: DicomSeriesGeometry(
          slicePositions: positions,
          orientation: orientation,
        ),
      );
    } catch (e) {
      if (e is DicomException) rethrow;
      throw DicomProcessingException('Failed to load DICOM series', e);
    }
  }
}
