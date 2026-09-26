import '../series/dicom_series.dart';

/// Study search query (QIDO-RS / C-FIND share this shape).
final class DicomStudyQuery {
  const DicomStudyQuery({this.patientName, this.studyDate, this.modality});
  final String? patientName;
  final String? studyDate;
  final String? modality;
}

/// Study handle returned by search.
final class DicomStudy {
  const DicomStudy({required this.studyUid, this.patientName});
  final String studyUid;
  final String? patientName;
}

/// DICOMweb client port — the application layer never sees HTTP.
abstract interface class DicomWebClient {
  Future<List<DicomStudy>> searchStudies(DicomStudyQuery query);
  Future<DicomSeries> retrieveSeries(String studyUid, String seriesUid);
}

/// DIMSE client port — the application layer never sees TCP/association.
abstract interface class DicomDimseClient {
  Future<void> store(Object object);
  Future<List<DicomStudy>> find(Object query);
  Future<void> move(Object request);
}
