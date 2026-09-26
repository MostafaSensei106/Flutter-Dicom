import 'dicom_geometry.dart';
import 'dicom_pixel_data.dart';
import 'dicom_tag_id.dart';
import 'dicom_windowing.dart';

/// Imaging modality relevant for display defaults.
enum DicomModality {
  ct,
  mr,
  xa,
  us,
  cr,
  dx,
  mg,
  pt,
  nm,
  unknown;

  static DicomModality parse(String? raw) {
    return switch (raw?.trim().toUpperCase()) {
      'CT' => DicomModality.ct,
      'MR' => DicomModality.mr,
      'XA' => DicomModality.xa,
      'US' => DicomModality.us,
      'CR' => DicomModality.cr,
      'DX' => DicomModality.dx,
      'MG' => DicomModality.mg,
      'PT' => DicomModality.pt,
      'NM' => DicomModality.nm,
      _ => DicomModality.unknown,
    };
  }
}

/// Transfer syntax relevant for capability reporting.
enum DicomTransferSyntax {
  implicitLittleEndian,
  explicitLittleEndian,
  explicitBigEndian,
  jpegBaseline,
  jpegLossless,
  jpeg2000,
  jpeg2000Lossless,
  rle,
  unknown;

  static DicomTransferSyntax parse(String? uid) {
    return switch (uid?.trim()) {
      '1.2.840.10008.1.2' => DicomTransferSyntax.implicitLittleEndian,
      '1.2.840.10008.1.2.1' => DicomTransferSyntax.explicitLittleEndian,
      '1.2.840.10008.1.2.2' => DicomTransferSyntax.explicitBigEndian,
      '1.2.840.10008.1.2.4.50' => DicomTransferSyntax.jpegBaseline,
      '1.2.840.10008.1.2.4.70' => DicomTransferSyntax.jpegLossless,
      '1.2.840.10008.1.2.4.90' => DicomTransferSyntax.jpeg2000,
      '1.2.840.10008.1.2.4.91' => DicomTransferSyntax.jpeg2000Lossless,
      '1.2.840.10008.1.2.5' => DicomTransferSyntax.rle,
      _ => DicomTransferSyntax.unknown,
    };
  }
}

/// Domain metadata contract — typed, nullable, no `"Unknown"` sentinels.
///
/// This is the public type. The FRB-generated struct stays internal and is
/// mapped to this via the infrastructure adapter, so the public API never
/// depends on codegen output.
final class DicomMetadata {
  const DicomMetadata({
    this.patientName,
    this.patientId,
    this.patientSex,
    this.modality,
    required this.rows,
    required this.columns,
    required this.bitsAllocated,
    required this.bitsStored,
    required this.highBit,
    required this.pixelRepresentation,
    required this.samplesPerPixel,
    required this.photometricInterpretation,
    required this.numberOfFrames,
    this.pixelSpacing,
    this.imagerPixelSpacing,
    this.imageOrientationPatient,
    this.imagePositionPatient,
    this.windowPresets = const [],
    this.transferSyntax = DicomTransferSyntax.unknown,
    this.extraTags = const {},
  });

  final String? patientName;
  final String? patientId;
  final String? patientSex;
  final DicomModality? modality;
  final int rows;
  final int columns;
  final int bitsAllocated;
  final int bitsStored;
  final int highBit;
  final DicomPixelRepresentation pixelRepresentation;
  final int samplesPerPixel;
  final DicomPhotometricInterpretation photometricInterpretation;
  final int numberOfFrames;
  final DicomPixelSpacing? pixelSpacing;
  final DicomPixelSpacing? imagerPixelSpacing;
  final DicomOrientation? imageOrientationPatient;
  final DicomPosition? imagePositionPatient;

  /// All window center/width pairs from the header (VM 2+ preserved).
  final List<DicomWindow> windowPresets;
  final DicomTransferSyntax transferSyntax;

  /// Raw tag fallback for vendor / unknown tags.
  final Map<DicomTagId, Object?> extraTags;

  /// Default window: first header preset, else modality fallback.
  DicomWindow get defaultWindow => windowPresets.isNotEmpty
      ? windowPresets.first
      : (DicomWindowPreset.forImage(this) ??
          const DicomWindow(center: 40, width: 400));

  /// Unknown-tag access without growing this class.
  T? tag<T>(DicomTagId id) {
    final value = extraTags[id];
    return value is T ? value : null;
  }

  /// Best available acquisition date, when supplied by the adapter.
  DateTime? get bestDate => tag<DateTime>(DicomTagId.studyDate);

  int get width => columns;
  int get height => rows;
}
