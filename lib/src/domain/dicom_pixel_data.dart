import 'dart:typed_data';

/// Signedness of stored pixels (0028,0103).
enum DicomPixelRepresentation {
  /// Unsigned stored pixels.
  unsigned,

  /// Signed stored pixels.
  signed;

  /// Resolves raw Pixel Representation to its enum value.
  static DicomPixelRepresentation fromRaw(final int raw) => raw == 1
      ? DicomPixelRepresentation.signed
      : DicomPixelRepresentation.unsigned;
}

/// Photometric interpretation relevant for display.
enum DicomPhotometricInterpretation {
  /// Minimum values display as white (inversion required).
  monochrome1,

  /// Minimum values display as black.
  monochrome2,

  /// Interleaved RGB color.
  rgb,

  /// Palette color LUT.
  palette,

  /// Unknown or unsupported interpretation.
  unknown;

  /// `true` when minimum values display as white (inversion required).
  bool get isInverted => this == DicomPhotometricInterpretation.monochrome1;

  /// Parses a Photometric Interpretation string.
  static DicomPhotometricInterpretation parse(final String? raw) {
    final v = (raw ?? '').trim().toUpperCase();
    return switch (v) {
      'MONOCHROME1' => DicomPhotometricInterpretation.monochrome1,
      'MONOCHROME2' => DicomPhotometricInterpretation.monochrome2,
      final s when s.startsWith('RGB') || s.startsWith('YBR') =>
        DicomPhotometricInterpretation.rgb,
      final s when s.startsWith('PALETTE') =>
        DicomPhotometricInterpretation.palette,
      _ => DicomPhotometricInterpretation.unknown,
    };
  }
}

/// Decoded pixel buffer kind.
enum DicomPixelFormat {
  /// Signed 16-bit monochrome.
  int16,

  /// Unsigned 8-bit monochrome.
  uint8,

  /// Unsigned 16-bit monochrome.
  uint16,

  /// Interleaved 8-bit RGB.
  rgb8,

  /// 32-bit float samples.
  float32,
}

/// Stored-value → modality-value transformation (Rescale Slope/Intercept +
/// representation). The viewer, ROI, and probe share this — HU math lives in
/// exactly one place.
final class DicomPixelTransform {
  /// Creates a stored-to-modality value transform.
  const DicomPixelTransform({
    this.rescaleSlope = 1.0,
    this.rescaleIntercept = 0.0,
    this.representation = DicomPixelRepresentation.unsigned,
    this.bitsAllocated = 16,
  });

  /// Rescale slope (0028,1053).
  final double rescaleSlope;

  /// Rescale intercept (0028,1052).
  final double rescaleIntercept;

  /// Signedness of stored pixels.
  final DicomPixelRepresentation representation;

  /// Bits allocated per sample.
  final int bitsAllocated;

  /// `true` for unsigned 16-bit data stored with the `-32768` offset.
  bool get isOffsetUnsigned16 =>
      representation == DicomPixelRepresentation.unsigned && bitsAllocated > 8;

  /// Maps a stored value to its modality value (HU for CT).
  double toModalityValue(final double raw) {
    final trueValue = isOffsetUnsigned16 ? raw + 32768.0 : raw;
    return trueValue * rescaleSlope + rescaleIntercept;
  }
}

/// Decoded pixel container. The renderer consumes this — never transfer
/// syntaxes, planar configuration, or packing details.
sealed class DicomPixelData {
  const DicomPixelData();

  /// Image width in pixels.
  int get width;

  /// Image height in pixels.
  int get height;

  /// Zero-based frame index.
  int get frameIndex;

  /// Decoded buffer kind.
  DicomPixelFormat get format;

  /// Pixel count (RGB counts pixels, not components).
  int get length;

  /// Stored-to-modality value transform.
  DicomPixelTransform get transform;

  /// Modality value at flat [index].
  double modalityAt(final int index);
}

/// 16-bit monochrome frame (the common diagnostic case).
final class DicomInt16PixelData extends DicomPixelData {
  /// Creates 16-bit monochrome pixel data.
  const DicomInt16PixelData({
    required this.buffer,
    required this.width,
    required this.height,
    this.frameIndex = 0,
    this.transform = const DicomPixelTransform(),
  });

  /// Raw 16-bit pixel buffer.
  final Int16List buffer;

  @override
  final int width;
  @override
  final int height;
  @override
  final int frameIndex;
  @override
  final DicomPixelTransform transform;

  @override
  DicomPixelFormat get format => DicomPixelFormat.int16;

  @override
  int get length => buffer.length;

  @override
  double modalityAt(final int index) => transform.toModalityValue(
        buffer[index].toDouble(),
      );
}

/// 8-bit monochrome frame.
final class DicomUint8PixelData extends DicomPixelData {
  /// Creates 8-bit monochrome pixel data.
  const DicomUint8PixelData({
    required this.buffer,
    required this.width,
    required this.height,
    this.frameIndex = 0,
    this.transform = const DicomPixelTransform(bitsAllocated: 8),
  });

  /// Raw 8-bit pixel buffer.
  final Uint8List buffer;

  @override
  final int width;
  @override
  final int height;
  @override
  final int frameIndex;
  @override
  final DicomPixelTransform transform;

  @override
  DicomPixelFormat get format => DicomPixelFormat.uint8;

  @override
  int get length => buffer.length;

  @override
  double modalityAt(final int index) => transform.toModalityValue(
        buffer[index].toDouble(),
      );
}

/// Interleaved RGB frame.
final class DicomRgbPixelData extends DicomPixelData {
  /// Creates interleaved RGB pixel data.
  const DicomRgbPixelData({
    required this.buffer,
    required this.width,
    required this.height,
    this.frameIndex = 0,
    this.transform = const DicomPixelTransform(bitsAllocated: 8),
  });

  /// Raw interleaved RGB buffer.
  final Uint8List buffer;

  @override
  final int width;
  @override
  final int height;
  @override
  final int frameIndex;
  @override
  final DicomPixelTransform transform;

  @override
  DicomPixelFormat get format => DicomPixelFormat.rgb8;

  @override
  int get length => buffer.length ~/ 3;

  /// Luminance-derived modality value at pixel [index].
  @override
  double modalityAt(final int index) {
    final r = buffer[index * 3].toDouble();
    final g = buffer[index * 3 + 1].toDouble();
    final b = buffer[index * 3 + 2].toDouble();
    return transform.toModalityValue(0.299 * r + 0.587 * g + 0.114 * b);
  }
}

/// Unsigned 16-bit frame (e.g. some MR / XA encodings).
final class DicomUint16PixelData extends DicomPixelData {
  /// Creates unsigned 16-bit pixel data.
  const DicomUint16PixelData({
    required this.buffer,
    required this.width,
    required this.height,
    this.frameIndex = 0,
    this.transform = const DicomPixelTransform(),
  });

  /// Raw unsigned 16-bit pixel buffer.
  final Uint16List buffer;

  @override
  final int width;
  @override
  final int height;
  @override
  final int frameIndex;
  @override
  final DicomPixelTransform transform;

  @override
  DicomPixelFormat get format => DicomPixelFormat.uint16;

  @override
  int get length => buffer.length;

  @override
  double modalityAt(final int index) => transform.toModalityValue(
        buffer[index].toDouble(),
      );
}

/// 32-bit float frame (e.g. parametric maps).
final class DicomFloat32PixelData extends DicomPixelData {
  /// Creates 32-bit float pixel data.
  const DicomFloat32PixelData({
    required this.buffer,
    required this.width,
    required this.height,
    this.frameIndex = 0,
    this.transform = const DicomPixelTransform(bitsAllocated: 32),
  });

  /// Raw 32-bit float pixel buffer.
  final Float32List buffer;

  @override
  final int width;
  @override
  final int height;
  @override
  final int frameIndex;
  @override
  final DicomPixelTransform transform;

  @override
  DicomPixelFormat get format => DicomPixelFormat.float32;

  @override
  int get length => buffer.length;

  @override
  double modalityAt(final int index) => transform.toModalityValue(
        buffer[index].toDouble(),
      );
}
