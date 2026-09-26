import '../domain/dicom_frame.dart';
import '../domain/dicom_geometry.dart';
import '../domain/dicom_source.dart';

/// Series load tuning.
final class DicomSeriesLoadOptions {
  const DicomSeriesLoadOptions({this.metadataOnly = false});
  final bool metadataOnly;
}

/// An ordered stack of slices forming one series.
final class DicomSeries {
  const DicomSeries({required this.frames, required this.geometry});

  final List<DicomFrameReference> frames;
  final DicomSeriesGeometry geometry;

  int get sliceCount => frames.length;

  DicomFrameReference slice(int index) => frames[index];
}

/// Spatial context of a series (slice positions along the normal).
final class DicomSeriesGeometry {
  const DicomSeriesGeometry({this.slicePositions = const [], this.orientation});
  final List<double> slicePositions;
  final DicomOrientation? orientation;
}

/// Series loader port — filesystem / DICOMweb adapters hide here.
abstract interface class DicomSeriesLoader {
  Future<DicomSeries> load(
    DicomSource source, {
    DicomSeriesLoadOptions options = const DicomSeriesLoadOptions(),
  });
}
