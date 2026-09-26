import '../../domain/dicom_frame.dart';
import '../../domain/dicom_geometry.dart';
import '../../domain/dicom_source.dart';
import '../../errors/dicom_exception.dart';
import '../../rust/api/init.dart';
import '../../series/dicom_series.dart';
import 'rust_metadata_mapper.dart';

/// Rust-backed series loader mapping grouped slices onto the domain model.
///
/// Files are grouped by Series Instance UID in Rust; the largest group wins
/// (multi-series directories should be split by callers via QIDO/worklist).
/// Display order is spatial (Image Position projected onto the slice
/// normal) with an Instance Number fallback — never filesystem order.
final class RustDicomSeriesLoader implements DicomSeriesLoader {
  /// Creates a Rust-backed series loader.
  const RustDicomSeriesLoader({
    this.ordering = const SpatialSeriesOrdering(),
    this.fallbackOrdering = const InstanceNumberOrdering(),
  });

  /// Primary ordering (spatial by default).
  final SeriesOrderingStrategy ordering;

  /// Fallback when slices carry no spatial tags.
  final SeriesOrderingStrategy fallbackOrdering;

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

      final orientation = group.slices.isNotEmpty
          ? RustMetadataMapper.parseOrientation(
              group.slices.first.metadata.imageOrientationPatient,
            )
          : null;
      final pixelSpacing = group.slices.isNotEmpty
          ? DicomPixelSpacing.tryParse(
              group.slices.first.metadata.pixelSpacing,
            )
          : null;

      var frames = <DicomFrameReference>[
        for (var i = 0; i < group.slices.length; i++)
          DicomFrameReference(
            index: i,
            label: group.slices[i].filePath,
            position: RustMetadataMapper.parsePosition(
              group.slices[i].metadata.imagePositionPatient,
            ),
            instanceNumber: RustMetadataMapper.parseInstanceNumber(
              group.slices[i].metadata.instanceNumber,
            ),
            sliceLocation: group.slices[i].metadata.sliceLocation == 0
                ? null
                : group.slices[i].metadata.sliceLocation.toDouble(),
          ),
      ];
      final hasSpatial = orientation != null &&
          group.slices.any(
            (final s) =>
                RustMetadataMapper.parsePosition(
                  s.metadata.imagePositionPatient,
                ) !=
                null,
          );
      // Spatial when tags exist (even if already ordered); otherwise the
      // Instance Number fallback keeps tag-less directories deterministic.
      final sorted = hasSpatial
          ? ordering.sort(frames, orientation: orientation)
          : fallbackOrdering.sort(frames, orientation: orientation);
      frames = [
        for (var i = 0; i < sorted.length; i++)
          DicomFrameReference(
            index: i,
            label: sorted[i].label,
            position: sorted[i].position,
            instanceNumber: sorted[i].instanceNumber,
            sliceLocation: sorted[i].sliceLocation,
          ),
      ];

      final positions = <double>[
        for (var i = 0; i < frames.length; i++)
          ordering.slicePosition(frames[i], orientation: orientation) ??
              fallbackOrdering.slicePosition(
                frames[i],
                orientation: orientation,
              ) ??
              i.toDouble(),
      ];
      return DicomSeries(
        frames: frames,
        geometry: DicomSeriesGeometry(
          slicePositions: positions,
          orientation: orientation,
          pixelSpacing: pixelSpacing,
        ),
      );
    } catch (e) {
      if (e is DicomException) rethrow;
      throw DicomProcessingException('Failed to load DICOM series', e);
    }
  }
}
