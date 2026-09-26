import 'dicom_geometry.dart';
import 'dicom_pixel_data.dart';
import 'dicom_tag_id.dart';
import 'dicom_windowing.dart';

/// Transfer syntax relevant for capability reporting.
enum DicomTransferSyntax {
  /// Implicit VR little endian (default).
  implicitLittleEndian,

  /// Explicit VR little endian.
  explicitLittleEndian,

  /// Explicit VR big endian (retired).
  explicitBigEndian,

  /// JPEG baseline 8-bit lossy.
  jpegBaseline,

  /// JPEG lossless.
  jpegLossless,

  /// JPEG 2000 lossy.
  jpeg2000,

  /// JPEG 2000 lossless.
  jpeg2000Lossless,

  /// Run-length encoding.
  rle,

  /// Unknown or unlisted UID.
  unknown;

  /// Parses a Transfer Syntax UID (0002,0010).
  static DicomTransferSyntax parse(final String? uid) {
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
final class DicomMetadata implements HasModality {
  /// Creates domain metadata with typed header values.
  const DicomMetadata({
    required this.rows, required this.columns, required this.bitsAllocated, required this.bitsStored, required this.highBit, required this.pixelRepresentation, required this.samplesPerPixel, required this.photometricInterpretation, required this.numberOfFrames, this.patientName,
    this.patientId,
    this.patientSex,
    this.modality,
    this.pixelSpacing,
    this.imagerPixelSpacing,
    this.imageOrientationPatient,
    this.imagePositionPatient,
    this.windowPresets = const [],
    this.transferSyntax = DicomTransferSyntax.unknown,
    this.extraTags = const {},
  });

  /// Patient name (0010,0010).
  final String? patientName;

  /// Patient ID (0010,0020).
  final String? patientId;

  /// Patient sex (0010,0040).
  final String? patientSex;

  @override
  final DicomModality? modality;

  /// Image rows (0028,0010).
  final int rows;

  /// Image columns (0028,0011).
  final int columns;

  /// Bits allocated (0028,0100).
  final int bitsAllocated;

  /// Bits stored (0028,0101).
  final int bitsStored;

  /// High bit (0028,0102).
  final int highBit;

  /// Signedness of stored pixels (0028,0103).
  final DicomPixelRepresentation pixelRepresentation;

  /// Samples per pixel (0028,0002).
  final int samplesPerPixel;

  /// Photometric interpretation (0028,0004).
  final DicomPhotometricInterpretation photometricInterpretation;

  /// Number of frames (0028,0008).
  final int numberOfFrames;

  /// Pixel Spacing (0028,0030), when present.
  final DicomPixelSpacing? pixelSpacing;

  /// Imager Pixel Spacing (0018,1164), when present.
  final DicomPixelSpacing? imagerPixelSpacing;

  /// Image orientation (0020,0037), when present.
  final DicomOrientation? imageOrientationPatient;

  /// Image position (0020,0032), when present.
  final DicomPosition? imagePositionPatient;

  /// All window center/width pairs from the header (VM 2+ preserved).
  final List<DicomWindow> windowPresets;

  /// Transfer syntax of the dataset.
  final DicomTransferSyntax transferSyntax;

  /// Raw tag fallback for vendor / unknown tags.
  final Map<DicomTagId, Object?> extraTags;

  /// Default window: first header preset, else modality fallback.
  DicomWindow get defaultWindow => windowPresets.isNotEmpty
      ? windowPresets.first
      : (DicomWindowPreset.forImage(this) ??
          const DicomWindow(center: 40, width: 400));

  /// Unknown-tag access without growing this class.
  T? tag<T>(final DicomTagId id) {
    final value = extraTags[id];
    return value is T ? value : null;
  }

  /// Best available acquisition date, when supplied by the adapter.
  DateTime? get bestDate => tag<DateTime>(DicomTagId.studyDate);

  /// Image width in pixels (columns).
  int get width => columns;

  /// Image height in pixels (rows).
  int get height => rows;
}
