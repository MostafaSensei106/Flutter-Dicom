import 'dicom_dataset.dart';
import 'dicom_writer.dart';

/// Coded concept: (scheme, value, meaning).
///
/// Encodes as an 8-bit Concept Code item (0008,0100 / 0102 / 0104).
final class DicomCode {
  /// Creates a coded concept.
  const DicomCode({
    required this.scheme,
    required this.value,
    required this.meaning,
  });

  /// Coding scheme designator (0008,0102), e.g. `'DCM'`, `'SCT'`, `'UCUM'`.
  final String scheme;

  /// Code value (0008,0100), e.g. `'121071'`, `'373098007'`, `'mm'`.
  final String value;

  /// Code meaning (0008,0104).
  final String meaning;

  /// Builds the 3-element code dataset used inside code sequences.
  DicomDataset toDataset() {
    final b = DicomDatasetBuilder()
      ..text(0x0008, 0x0100, 'SH', value)
      ..text(0x0008, 0x0102, 'SH', scheme)
      ..text(0x0008, 0x0104, 'LO', meaning);
    return b.build();
  }
}

/// Structured Report content item (Composite tree node).
///
/// Value types covered: `CONTAINER`, `TEXT`, `CODE`, `NUM`. Containers nest
/// through Content Sequence (0040,A730) — the classic SR Composite.
sealed class SrContentItem {
  const SrContentItem();

  /// Concept name of this item (0040,A043), when coded.
  DicomCode? get conceptName;

  /// DICOM value type (0040,A040).
  String get valueType;

  /// Builds the item dataset (content sequence handled by the parent).
  DicomDataset toDataset();
}

/// Container grouping child items.
final class SrContainer extends SrContentItem {
  /// Creates a container with [items] and [continuity].
  const SrContainer({
    required this.concept,
    required this.items,
    this.continuity = 'SEPARATE',
  });

  /// Container concept name.
  final DicomCode concept;

  /// Nested content items.
  final List<SrContentItem> items;

  /// Continuity Of Content (0040,A050): SEPARATE or CONTINUOUS.
  final String continuity;

  @override
  DicomCode? get conceptName => concept;

  @override
  String get valueType => 'CONTAINER';

  @override
  DicomDataset toDataset() {
    final b = _base()
      ..text(0x0040, 0xA050, 'CS', continuity)
      ..contentSequence([for (final i in items) i.toDataset()]);
    return b.build();
  }

  DicomDatasetBuilder _base() => _itemBase(this);
}

/// Free-text observation.
final class SrText extends SrContentItem {
  /// Creates a text observation with [value].
  const SrText({required this.concept, required this.value});

  /// Concept name of the observation.
  final DicomCode concept;

  /// Text Value (0040,A160).
  final String value;

  @override
  DicomCode? get conceptName => concept;

  @override
  String get valueType => 'TEXT';

  @override
  DicomDataset toDataset() {
    final b = _itemBase(this)..text(0x0040, 0xA160, 'UT', value);
    return b.build();
  }
}

/// Coded observation (finding, diagnosis, qualitative result).
final class SrCode extends SrContentItem {
  /// Creates a coded observation selecting [value] for [concept].
  const SrCode({required this.concept, required this.value});

  /// Concept name of the observation.
  final DicomCode concept;

  /// Selected code (0040,A168).
  final DicomCode value;

  @override
  DicomCode? get conceptName => concept;

  @override
  String get valueType => 'CODE';

  @override
  DicomDataset toDataset() {
    final b = _itemBase(this);
    b.custom(
      0x0040,
      0xA168,
      'SQ',
      DicomWriter.encodeSequenceItems([value.toDataset()]),
    );
    return b.build();
  }
}

/// Numeric measurement with units.
final class SrNum extends SrContentItem {
  /// Creates a numeric measurement of [value] [units] for [concept].
  const SrNum({
    required this.concept,
    required this.value,
    required this.units,
  });

  /// Concept name of the measurement.
  final DicomCode concept;

  /// Numeric Value (0040,A30A).
  final double value;

  /// Measurement units (0040,08EA), e.g. UCUM `mm`.
  final DicomCode units;

  @override
  DicomCode? get conceptName => concept;

  @override
  String get valueType => 'NUM';

  @override
  DicomDataset toDataset() {
    final measured = DicomDatasetBuilder()
      ..text(0x0040, 0xA30A, 'DS', '$value')
      ..custom(
        0x0040,
        0x08EA,
        'SQ',
        DicomWriter.encodeSequenceItems([units.toDataset()]),
      );
    final b = _itemBase(this);
    b.custom(
      0x0040,
      0xA300,
      'SQ',
      DicomWriter.encodeSequenceItems([measured.build()]),
    );
    return b.build();
  }
}

/// Shared item prefix: Value Type + Concept Name Code Sequence.
DicomDatasetBuilder _itemBase(final SrContentItem item) {
  final b = DicomDatasetBuilder()
    ..text(0x0040, 0xA040, 'CS', item.valueType);
  final concept = item.conceptName;
  if (concept != null) {
    b.custom(
      0x0040,
      0xA043,
      'SQ',
      DicomWriter.encodeSequenceItems([concept.toDataset()]),
    );
  }
  return b;
}

/// A complete Structured Report document (Comprehensive SR SOP Class).
final class StructuredReport {
  /// Creates a report over [items] with study/series/SOP identity.
  const StructuredReport({
    required this.items,
    required this.studyUid,
    required this.seriesUid,
    required this.sopUid,
    this.patientName,
    this.patientId,
    this.modality = 'SR',
  });

  /// Top-level content items.
  final List<SrContentItem> items;

  /// Study Instance UID.
  final String studyUid;

  /// Series Instance UID.
  final String seriesUid;

  /// SOP Instance UID.
  final String sopUid;

  /// Patient name, when known.
  final String? patientName;

  /// Patient ID, when known.
  final String? patientId;

  /// Modality (0008,0060), always SR for reports.
  final String modality;

  /// Builds the report dataset (encode with [DicomWriter]).
  DicomDataset toDataset() {
    final b = DicomDatasetBuilder()
      ..sop(
        classUid: DicomSopClass.comprehensiveSr,
        instanceUid: sopUid,
      )
      ..patient(name: patientName, id: patientId)
      ..study(studyUid: studyUid)
      ..series(seriesUid: seriesUid, modality: modality)
      ..text(0x0040, 0xA491, 'CS', 'COMPLETE') // Completion Flag
      ..text(0x0040, 0xA493, 'CS', 'VERIFIED') // Verification Flag
      ..contentSequence([for (final i in items) i.toDataset()]);
    return b.build();
  }
}
