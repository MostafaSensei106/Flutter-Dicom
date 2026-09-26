/// Strongly-typed DICOM tag identifiers.
///
/// Unknown / vendor tags stay reachable via [DicomMetadata.tag] instead of
/// growing the metadata class into a God Object.
final class DicomTagId {
  const DicomTagId(this.group, this.element);

  /// Tag group (e.g. `0x0028`).
  final int group;

  /// Tag element (e.g. `0x0010`).
  final int element;

  static const rows = DicomTagId(0x0028, 0x0010);
  static const columns = DicomTagId(0x0028, 0x0011);
  static const pixelSpacing = DicomTagId(0x0028, 0x0030);
  static const imagerPixelSpacing = DicomTagId(0x0018, 0x1164);
  static const windowCenter = DicomTagId(0x0028, 0x1050);
  static const windowWidth = DicomTagId(0x0028, 0x1051);
  static const rescaleIntercept = DicomTagId(0x0028, 0x1052);
  static const rescaleSlope = DicomTagId(0x0028, 0x1053);
  static const photometricInterpretation = DicomTagId(0x0028, 0x0004);
  static const samplesPerPixel = DicomTagId(0x0028, 0x0002);
  static const bitsAllocated = DicomTagId(0x0028, 0x0100);
  static const bitsStored = DicomTagId(0x0028, 0x0101);
  static const highBit = DicomTagId(0x0028, 0x0102);
  static const pixelRepresentation = DicomTagId(0x0028, 0x0103);
  static const numberOfFrames = DicomTagId(0x0028, 0x0008);
  static const modality = DicomTagId(0x0008, 0x0060);
  static const patientName = DicomTagId(0x0010, 0x0010);
  static const patientId = DicomTagId(0x0010, 0x0020);
  static const patientSex = DicomTagId(0x0010, 0x0040);
  static const imagePositionPatient = DicomTagId(0x0020, 0x0032);
  static const imageOrientationPatient = DicomTagId(0x0020, 0x0037);
  static const sliceLocation = DicomTagId(0x0020, 0x1041);
  static const transferSyntaxUid = DicomTagId(0x0002, 0x0010);
  static const sopClassUid = DicomTagId(0x0008, 0x0016);
  static const studyDate = DicomTagId(0x0008, 0x0020);

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      other is DicomTagId &&
          runtimeType == other.runtimeType &&
          group == other.group &&
          element == other.element;

  @override
  int get hashCode => group.hashCode ^ element.hashCode;

  @override
  String toString() =>
      '(${group.toRadixString(16).padLeft(4, '0').toUpperCase()},'
      '${element.toRadixString(16).padLeft(4, '0').toUpperCase()})';
}
