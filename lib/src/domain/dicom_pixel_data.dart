import 'dart:typed_data';

/// Signedness of stored pixels (0028,0103).
enum DicomPixelRepresentation {
  unsigned,
  signed;

  static DicomPixelRepresentation fromRaw(int raw) =>
      raw == 1 ? DicomPixelRepresentation.signed : DicomPixelRepresentation.unsigned;
}

/// Photometric interpretation relevant for display.
enum DicomPhotometricInterpretation {
  monochrome1,
  monochrome2,
  rgb,
  palette,
  unknown;

  /// `true` when minimum values display as white (inversion required).
  bool get isInverted => this == DicomPhotometricInterpretation.monochrome1;

  static DicomPhotometricInterpretation parse(String? raw) {
    final v = (raw ?? '').trim().toUpperCase();
    return switch (v) {
      'MONOCHROME1' => DicomPhotometricInterpretation.monochrome1,
      'MONOCHROME2' => DicomPhotometricInterpretation.monochrome2,
      var s when s.startsWith('RGB') || s.startsWith('YBR') =>
        DicomPhotometricInterpretation.rgb,
      var s when s.startsWith('PALETTE') => DicomPhotometricInterpretation.palette,
      _ => DicomPhotometricInterpretation.unknown,
    };
  }
}

/// Decoded pixel buffer kind.
enum DicomPixelFormat {
  int16,
  uint8,
  uint16,
  rgb8,
  float32,
}

/// Stored-value → modality-value transformation (Rescale Slope/Intercept +
/// representation). The viewer, ROI, and probe share this — HU math lives in
/// exactly one place.
final class DicomPixelTransform {
  const DicomPixelTransform({
    this.rescaleSlope = 1.0,
    this.rescaleIntercept = 0.0,
    this.representation = DicomPixelRepresentation.unsigned,
    this.bitsAllocated = 16,
  });

  final double rescaleSlope;
  final double rescaleIntercept;
  final DicomPixelRepresentation representation;
  final int bitsAllocated;

  /// `true` for unsigned 16-bit data stored with the `-32768` offset.
  bool get isOffsetUnsigned16 =>
      representation == DicomPixelRepresentation.unsigned &&
      bitsAllocated > 8;

  /// Maps a stored value to its modality value (HU for CT).
  double toModalityValue(double raw) {
    final trueValue = isOffsetUnsigned16 ? raw + 32768.0 : raw;
    return trueValue * rescaleSlope + rescaleIntercept;
  }
}

/// Decoded pixel container. The renderer consumes this — never transfer
/// syntaxes, planar configuration, or packing details.
sealed class DicomPixelData {
  const DicomPixelData();

  int get width;
  int get height;
  int get frameIndex;
  DicomPixelFormat get format;
  int get length;
  DicomPixelTransform get transform;

  /// Modality value at flat [index].
  double modalityAt(int index);
}

/// 16-bit monochrome frame (the common diagnostic case).
final class DicomInt16PixelData extends DicomPixelData {
  const DicomInt16PixelData({
    required this.buffer,
    required this.width,
    required this.height,
    this.frameIndex = 0,
    this.transform = const DicomPixelTransform(),
  });

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
  double modalityAt(int index) => transform.toModalityValue(
    buffer[index].toDouble(),
  );
}

/// 8-bit monochrome frame.
final class DicomUint8PixelData extends DicomPixelData {
  const DicomUint8PixelData({
    required this.buffer,
    required this.width,
    required this.height,
    this.frameIndex = 0,
    this.transform = const DicomPixelTransform(bitsAllocated: 8),
  });

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
  double modalityAt(int index) => transform.toModalityValue(
    buffer[index].toDouble(),
  );
}

/// Interleaved RGB frame.
final class DicomRgbPixelData extends DicomPixelData {  const DicomRgbPixelData({
    required this.buffer,
    required this.width,
    required this.height,
    this.frameIndex = 0,
    this.transform = const DicomPixelTransform(bitsAllocated: 8),
  });

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
  double modalityAt(int index) {
    final r = buffer[index * 3].toDouble();
    final g = buffer[index * 3 + 1].toDouble();
    final b = buffer[index * 3 + 2].toDouble();
    return transform.toModalityValue(0.299 * r + 0.587 * g + 0.114 * b);
  }
}

/// Unsigned 16-bit frame (e.g. some MR / XA encodings).
final class DicomUint16PixelData extends DicomPixelData {
  const DicomUint16PixelData({
    required this.buffer,
    required this.width,
    required this.height,
    this.frameIndex = 0,
    this.transform = const DicomPixelTransform(),
  });

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
  double modalityAt(int index) => transform.toModalityValue(
    buffer[index].toDouble(),
  );
}

/// 32-bit float frame (e.g. parametric maps).
final class DicomFloat32PixelData extends DicomPixelData {
  const DicomFloat32PixelData({
    required this.buffer,
    required this.width,
    required this.height,
    this.frameIndex = 0,
    this.transform = const DicomPixelTransform(bitsAllocated: 32),
  });

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
  double modalityAt(int index) => transform.toModalityValue(
    buffer[index].toDouble(),
  );
}
