import 'dart:typed_data';

import '../application/ports/dicom_exporter.dart';
import '../domain/dicom_pixel_data.dart';
import '../domain/dicom_windowing.dart';

/// PNG exporter rendering windowed grayscale (what you see is what you get).
///
/// Only [DicomExportFormat.png] is implemented; JPEG/TIFF throw
/// [UnimplementedError]. Pixel values are mapped through [DicomWindowPreset.softTissue]-style
/// normalization when no window is supplied — pass an explicit window via
/// [PngDicomExporter.exportWindowed] for clinical exports.
final class PngDicomExporter implements DicomExporter {
  const PngDicomExporter();

  @override
  Future<Uint8List> export(
    final DicomPixelData pixels, {
    required final DicomExportFormat format,
    final DicomExportOptions options = const DicomExportOptions(),
  }) {
    if (format != DicomExportFormat.png) {
      throw UnimplementedError('$format export is not implemented yet');
    }
    return exportWindowed(pixels, const DicomWindow(center: 40, width: 400));
  }

  /// Exports [pixels] through [window] as an 8-bit grayscale PNG.
  Future<Uint8List> exportWindowed(
    final DicomPixelData pixels,
    final DicomWindow window,
  ) async {
    final width = pixels.width;
    final height = pixels.height;
    final gray = Uint8List(width * height);
    for (var i = 0; i < gray.length; i++) {
      gray[i] =
          (window.apply(pixels.modalityAt(i)) * 255).round().clamp(0, 255);
    }
    return _encodeGrayscalePng(width, height, gray);
  }

  /// Minimal 8-bit grayscale PNG encoder (no external dependencies).
  static Uint8List _encodeGrayscalePng(
    final int width,
    final int height,
    final Uint8List gray,
  ) {
    final out = BytesBuilder();
    out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    void chunk(final String type, final List<int> data) {
      final typeBytes = type.codeUnits;
      out.add(_u32(data.length));
      out.add(typeBytes);
      out.add(data);
      final crc = _Crc32();
      crc.add(typeBytes);
      crc.add(data);
      out.add(_u32(crc.value));
    }

    final ihdr = BytesBuilder()
      ..add(_u32(width))
      ..add(_u32(height))
      ..add([8, 0, 0, 0, 0]); // 8-bit, grayscale, no interlace
    chunk('IHDR', ihdr.toBytes());

    final raw = BytesBuilder();
    for (var y = 0; y < height; y++) {
      raw.addByte(0); // filter: none
      raw.add(gray.sublist(y * width, (y + 1) * width));
    }
    chunk('IDAT', _zlibStored(raw.toBytes()));
    chunk('IEND', const []);
    return out.toBytes();
  }

  /// Minimal zlib stream using only stored (uncompressed) deflate blocks.
  ///
  /// The SDK flavor in use ships `dart:convert` without zlib, so compression
  /// is implemented directly (RFC 1950 wrapper + RFC 1951 stored blocks +
  /// Adler-32). Output is a fully valid zlib stream decoders accept.
  static Uint8List _zlibStored(final Uint8List data) {
    final out = BytesBuilder();
    out.add([0x78, 0x01]); // CMF/FLG: deflate, 32K window, FCHECK valid
    var offset = 0;
    if (data.isEmpty) {
      out.add([0x01, 0x00, 0x00, 0xFF, 0xFF]); // empty final stored block
    }
    while (offset < data.length) {
      final remaining = data.length - offset;
      final chunkSize = remaining > 65535 ? 65535 : remaining;
      final isFinal = offset + chunkSize >= data.length;
      out.addByte(isFinal ? 0x01 : 0x00); // BFINAL + BTYPE=00 (stored)
      out.addByte(chunkSize & 0xFF);
      out.addByte((chunkSize >> 8) & 0xFF);
      out.addByte((~chunkSize) & 0xFF);
      out.addByte(((~chunkSize) >> 8) & 0xFF);
      out.add(data.sublist(offset, offset + chunkSize));
      offset += chunkSize;
    }
    var a = 1;
    var b = 0;
    for (final byte in data) {
      a = (a + byte) % 65521;
      b = (b + a) % 65521;
    }
    final adler = (b << 16) | a;
    out.add(_u32(adler));
    return out.toBytes();
  }

  static List<int> _u32(final int v) =>
      [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
}

/// CRC-32 (ISO 3309) used by PNG chunks.
final class _Crc32 {
  static final List<int> _table = List.generate(256, (final n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    return c;
  });

  int _crc = 0xFFFFFFFF;

  void add(final List<int> bytes) {
    for (final b in bytes) {
      _crc = _table[(_crc ^ b) & 0xFF] ^ (_crc >>> 8);
    }
  }

  int get value => (_crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
