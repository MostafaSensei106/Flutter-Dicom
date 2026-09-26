
/// Strongly-typed DICOM tag identifiers.
///
/// Unknown / vendor tags stay reachable via [DicomMetadata.tag] instead of
/// growing the metadata class into a God Object.
final class DicomTagId {
  /// Creates a tag identifier from [group] and [element].
  const DicomTagId(this.group, this.element);

  /// Tag group (e.g. `0x0028`).
  final int group;

  /// Tag element (e.g. `0x0010`).
  final int element;

  /// Rows (0028,0010).
  static const rows = DicomTagId(0x0028, 0x0010);

  /// Columns (0028,0011).
  static const columns = DicomTagId(0x0028, 0x0011);

  /// Pixel Spacing (0028,0030).
  static const pixelSpacing = DicomTagId(0x0028, 0x0030);

  /// Imager Pixel Spacing (0018,1164).
  static const imagerPixelSpacing = DicomTagId(0x0018, 0x1164);

  /// Window Center (0028,1050).
  static const windowCenter = DicomTagId(0x0028, 0x1050);

  /// Window Width (0028,1051).
  static const windowWidth = DicomTagId(0x0028, 0x1051);

  /// Rescale Intercept (0028,1052).
  static const rescaleIntercept = DicomTagId(0x0028, 0x1052);

  /// Rescale Slope (0028,1053).
  static const rescaleSlope = DicomTagId(0x0028, 0x1053);

  /// Photometric Interpretation (0028,0004).
  static const photometricInterpretation = DicomTagId(0x0028, 0x0004);

  /// Samples per Pixel (0028,0002).
  static const samplesPerPixel = DicomTagId(0x0028, 0x0002);

  /// Bits Allocated (0028,0100).
  static const bitsAllocated = DicomTagId(0x0028, 0x0100);

  /// Bits Stored (0028,0101).
  static const bitsStored = DicomTagId(0x0028, 0x0101);

  /// High Bit (0028,0102).
  static const highBit = DicomTagId(0x0028, 0x0102);

  /// Pixel Representation (0028,0103).
  static const pixelRepresentation = DicomTagId(0x0028, 0x0103);

  /// Number of Frames (0028,0008).
  static const numberOfFrames = DicomTagId(0x0028, 0x0008);

  /// Modality (0008,0060).
  static const modality = DicomTagId(0x0008, 0x0060);

  /// Patient Name (0010,0010).
  static const patientName = DicomTagId(0x0010, 0x0010);

  /// Patient ID (0010,0020).
  static const patientId = DicomTagId(0x0010, 0x0020);

  /// Patient Sex (0010,0040).
  static const patientSex = DicomTagId(0x0010, 0x0040);

  /// Image Position (Patient) (0020,0032).
  static const imagePositionPatient = DicomTagId(0x0020, 0x0032);

  /// Image Orientation (Patient) (0020,0037).
  static const imageOrientationPatient = DicomTagId(0x0020, 0x0037);

  /// Slice Location (0020,1041).
  static const sliceLocation = DicomTagId(0x0020, 0x1041);

  /// Transfer Syntax UID (0002,0010).
  static const transferSyntaxUid = DicomTagId(0x0002, 0x0010);

  /// SOP Class UID (0008,0016).
  static const sopClassUid = DicomTagId(0x0008, 0x0016);

  /// Study Date (0008,0020).
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
