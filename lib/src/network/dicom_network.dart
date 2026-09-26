import 'dart:typed_data';

import '../series/dicom_series.dart';
import '../writing/dicom_dataset.dart';

/// Study search query (QIDO-RS / C-FIND share this shape).
final class DicomStudyQuery {
  /// Creates a study query with optional match filters.
  const DicomStudyQuery({this.patientName, this.studyDate, this.modality});

  /// Patient name filter, when set.
  final String? patientName;

  /// Study date filter (`YYYYMMDD`), when set.
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

/// C-FIND result carrying the study identity plus matched keys.
final class DicomFindResult {
  /// Creates a find result for [studyUid].
  const DicomFindResult({
    required this.studyUid,
    this.patientName,
    this.studyDate,
    this.modality,
  });

  /// Study instance UID.
  final String studyUid;

  /// Patient name from the identifier, when present.
  final String? patientName;

  /// Study date from the identifier, when present.
  final DateTime? studyDate;

  /// Modality from the identifier, when present.
  final String? modality;
}

/// DICOMweb client port — the application layer never sees HTTP.
abstract interface class DicomWebClient {
  /// Searches studies matching [query] (QIDO-RS).
  Future<List<DicomStudy>> searchStudies(final DicomStudyQuery query);

  /// Retrieves the series [seriesUid] within study [studyUid] (WADO-RS).
  Future<DicomSeries> retrieveSeries(
      final String studyUid, final String seriesUid);

  /// Retrieves one instance as raw file bytes (WADO-RS).
  Future<Uint8List> retrieveInstance(
      final String studyUid,
      final String seriesUid,
      final String instanceUid);

  /// Stores one instance from raw file bytes (STOW-RS).
  Future<void> storeInstance(final Uint8List dicomBytes);
}

/// DIMSE association lifecycle (state machine, never bare booleans).
enum DimseAssocState {
  /// No transport connection.
  disconnected,

  /// Association request sent, awaiting acceptance.
  associating,

  /// Association accepted, commands may flow.
  associated,

  /// Release requested, awaiting confirmation.
  releasing,
}

/// DIMSE command dispatched through the client (Command pattern).
///
/// Echo/Store/Find execute over the association; Move/Get are typed for
/// callers but need an inbound Storage SCP, so they fail fast with a
/// documented [UnimplementedError] instead of half-working.
sealed class DimseCommand {
  const DimseCommand();
}

/// C-ECHO (verification) command.
final class DimseEchoCommand extends DimseCommand {
  /// Creates a verification command.
  const DimseEchoCommand();
}

/// C-STORE command carrying a dataset to store on the remote AE.
final class DimseStoreCommand extends DimseCommand {
  /// Creates a store command for [dataset].
  const DimseStoreCommand(this.dataset);

  /// Dataset encoded and sent as the command data set.
  final DicomDataset dataset;
}

/// C-FIND command carrying a study-level query.
final class DimseFindCommand extends DimseCommand {
  /// Creates a find command for [query].
  const DimseFindCommand(this.query);

  /// Study-level query keys.
  final DicomStudyQuery query;
}

/// C-MOVE command (needs an inbound Storage SCP — typed, not yet executed).
final class DimseMoveCommand extends DimseCommand {
  /// Creates a move command for [query] to [destinationAe].
  const DimseMoveCommand(this.query, this.destinationAe);

  /// Study-level query keys.
  final DicomStudyQuery query;

  /// Move destination AE title.
  final String destinationAe;
}

/// C-GET command (needs an inbound Storage SCP — typed, not yet executed).
final class DimseGetCommand extends DimseCommand {
  /// Creates a get command for [query].
  const DimseGetCommand(this.query);

  /// Study-level query keys.
  final DicomStudyQuery query;
}

/// DIMSE client port — the application layer never sees TCP/association.
///
/// M7 executes Echo/Store/Find over Explicit LE; Move/Get stay typed for a
/// future inbound Storage SCP.
abstract interface class DicomDimseClient {
  /// Current association state.
  DimseAssocState get state;

  /// Broadcast of association state transitions.
  Stream<DimseAssocState> get states;

  /// Associates with a remote AE (moves disconnected → associated).
  Future<void> associate({
    required final String host,
    required final int port,
    final String callingAe = 'FLUTTER_DICOM',
    final String calledAe = 'ANY-SCP',
  });

  /// Executes [command], returning command-specific results.
  ///
  /// Returns `Duration` (Echo RTT), `void` (Store), or
  /// `List<DicomFindResult>` (Find).
  Future<Object?> execute(final DimseCommand command);

  /// Releases the association gracefully (associated → disconnected).
  Future<void> release();

  /// Aborts the association without confirmation.
  Future<void> abort();

  /// Releases socket resources.
  void dispose();
}
