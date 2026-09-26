import '../domain/dicom_frame.dart';
import '../domain/dicom_geometry.dart';
import '../domain/dicom_source.dart';

/// Series load tuning.
final class DicomSeriesLoadOptions {
  /// Creates load options; [metadataOnly] skips pixel loading.
  const DicomSeriesLoadOptions({this.metadataOnly = false});

  /// Whether to load metadata only and skip pixel data.
  final bool metadataOnly;
}

/// An ordered stack of slices forming one series.
final class DicomSeries {
  /// Creates a series from ordered [frames] with spatial [geometry].
  const DicomSeries({required this.frames, required this.geometry});

  /// Ordered slice frames of this series.
  final List<DicomFrameReference> frames;

  /// Spatial context of the stacked slices.
  final DicomSeriesGeometry geometry;

  /// Number of slices in the series.
  int get sliceCount => frames.length;

  /// Returns the slice frame at [index].
  DicomFrameReference slice(final int index) => frames[index];
}

/// Spatial context of a series (slice positions along the normal).
final class DicomSeriesGeometry {
  /// Creates series geometry with optional slice positions and orientation.
  const DicomSeriesGeometry({this.slicePositions = const [], this.orientation});

  /// Slice positions along the series normal.
  final List<double> slicePositions;

  /// Image orientation of the series, when known.
  final DicomOrientation? orientation;
}

/// Series loader port — filesystem / DICOMweb adapters hide here.
abstract interface class DicomSeriesLoader {
  /// Loads a series from [source] with the given [options].
  Future<DicomSeries> load(
    final DicomSource source, {
    final DicomSeriesLoadOptions options = const DicomSeriesLoadOptions(),
  });
}
