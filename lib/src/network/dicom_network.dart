import '../series/dicom_series.dart';

/// Study search query (QIDO-RS / C-FIND share this shape).
final class DicomStudyQuery {
  /// Creates a study query with optional match filters.
  const DicomStudyQuery({this.patientName, this.studyDate, this.modality});

  /// Patient name filter, when set.
  final String? patientName;

  /// Study date filter, when set.
  final String? studyDate;

  /// Modality filter, when set.
  final String? modality;
}

/// Study handle returned by search.
final class DicomStudy {
  /// Creates a study handle with a [studyUid] and optional patient name.
  const DicomStudy({required this.studyUid, this.patientName});

  /// Study instance UID identifying the study.
  final String studyUid;

  /// Patient name associated with the study, when known.
  final String? patientName;
}

/// DICOMweb client port — the application layer never sees HTTP.
abstract interface class DicomWebClient {
  /// Searches studies matching [query].
  Future<List<DicomStudy>> searchStudies(final DicomStudyQuery query);

  /// Retrieves the series [seriesUid] within study [studyUid].
  Future<DicomSeries> retrieveSeries(
      final String studyUid, final String seriesUid);
}

/// DIMSE client port — the application layer never sees TCP/association.
abstract interface class DicomDimseClient {
  /// Stores [object] on the remote AE.
  Future<void> store(final Object object);

  /// Finds studies matching [query].
  Future<List<DicomStudy>> find(final Object query);

  /// Requests the remote AE to move data per [request].
  Future<void> move(final Object request);
}
