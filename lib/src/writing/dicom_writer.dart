import 'dart:io';
import 'dart:typed_data';

import 'dicom_dataset.dart';

/// DICOM file writer: Explicit VR Little Endian, 128-byte preamble.
///
/// Encodes what [DicomDatasetBuilder] produces (Secondary Capture, SR, …).
/// Sequences use undefined length; every other element uses defined length.
/// Group 0002 (file meta) is writer-owned — datasets never carry it.
abstract final class DicomWriter {
  /// VRs with a 32-bit length field in Explicit VR.
  static const longVrs = {'OB', 'OD', 'OF', 'OL', 'OV', 'OW', 'SQ', 'UC', 'UR', 'UT', 'UN'};

  /// Encodes [dataset] into a complete `.dcm` file image.
  static Uint8List encode(
    final DicomDataset dataset, {
    final String transferSyntaxUid = DicomSopClass.explicitLe,
  }) {
    final sopClass = dataset.sopClassUid ?? DicomSopClass.secondaryCapture;
    final sopInstance = dataset.sopInstanceUid ?? DicomUid.generate();
    final meta = _meta(sopClass, sopInstance, transferSyntaxUid);
    final out = BytesBuilder();
    out.add(Uint8List(128)); // preamble
    out.add([0x44, 0x49, 0x43, 0x4D]); // 'DICM'
    out.add(meta);
    out.add(encodeElements(dataset.elements));
    return out.toBytes();
  }

  /// Encodes [dataset] and writes it to [path].
  static Future<void> writeFile(
    final DicomDataset dataset,
    final String path, {
    final String transferSyntaxUid = DicomSopClass.explicitLe,
  }) async {
    await File(path).writeAsBytes(
      encode(dataset, transferSyntaxUid: transferSyntaxUid),
    );
  }

  /// Encodes dataset elements sorted by tag (group 0002 excluded).
  static Uint8List encodeElements(final List<DicomDataElement> elements) {
    final sorted = List.of(elements)
      ..sort((final a, final b) {
        final g = a.group.compareTo(b.group);
        return g != 0 ? g : a.element.compareTo(b.element);
      });
    final out = BytesBuilder();
    for (final e in sorted) {
      if (e.group == 0x0002) continue;
      out.add(_u16(e.group));
      out.add(_u16(e.element));
      final vr = e.vr.length == 2 ? e.vr : 'UN';
      out.add(vr.codeUnits);
      final bytes = e.bytes.length.isEven ? e.bytes : Uint8List.fromList([...e.bytes, 0x00]);
      if (longVrs.contains(vr)) {
        out.add([0x00, 0x00]);
        // Sequences are always undefined length (delimited); every other
        // long VR uses a defined length.
        out.add(_u32(vr == 'SQ' ? 0xFFFFFFFF : bytes.length));
      } else {
        out.add(_u16(bytes.length));
      }
      out.add(bytes);
      if (vr == 'SQ') {
        out.add(_u16(0xFFFE));
        out.add(_u16(0xE0DD));
        out.add(_u32(0)); // sequence delimitation
      }
    }
    return out.toBytes();
  }

  /// Encodes nested datasets as undefined-length sequence items.
  static Uint8List encodeSequenceItems(final List<DicomDataset> items) {
    final out = BytesBuilder();
    for (final item in items) {
      out.add(_u16(0xFFFE));
      out.add(_u16(0xE000));
      out.add(_u32(0xFFFFFFFF)); // item, undefined length
      out.add(encodeElements(item.elements));
      out.add(_u16(0xFFFE));
      out.add(_u16(0xE00D));
      out.add(_u32(0)); // item delimitation
    }
    return out.toBytes();
  }

  /// File meta group (0002) with a leading group-length element.
  ///
  /// File meta is Explicit VR: UI takes the 16-bit length form (PS3.5 7.1.2 —
  /// only OB/OD/OF/OL/OV/OW/SQ/UC/UR/UT/UN use reserved + 32-bit length).
  static Uint8List _meta(
    final String sopClass,
    final String sopInstance,
    final String transferSyntax,
  ) {
    final body = BytesBuilder();
    void ui(final int element, final String value) {
      body.add(_u16(0x0002));
      body.add(_u16(element));
      body.add('UI'.codeUnits);
      final bytes = _even(_ascii(value), 0x00);
      body.add(_u16(bytes.length));
      body.add(bytes);
    }

    void sh(final int element, final String value) {
      body.add(_u16(0x0002));
      body.add(_u16(element));
      body.add('SH'.codeUnits);
      final bytes = _even(_ascii(value), 0x20);
      body.add(_u16(bytes.length));
      body.add(bytes);
    }

    ui(0x0002, sopClass);
    ui(0x0003, sopInstance);
    ui(0x0010, transferSyntax);
    ui(0x0012, '2.25.2882753235109249'); // SDK implementation UID (dev)
    sh(0x0013, 'FLUTTER_DICOM_020');
    final bodyBytes = body.toBytes();
    final out = BytesBuilder();
    out.add(_u16(0x0002));
    out.add(_u16(0x0000));
    out.add('UL'.codeUnits);
    out.add(_u16(4));
    out.add(_u32(bodyBytes.length));
    out.add(bodyBytes);
    return out.toBytes();
  }

  static List<int> _ascii(final String s) =>
      [for (final c in s.codeUnits) c <= 255 ? c : 0x3F];

  static Uint8List _even(final List<int> bytes, final int pad) =>
      bytes.length.isEven
          ? Uint8List.fromList(bytes)
          : Uint8List.fromList([...bytes, pad]);

  static List<int> _u16(final int v) => [v & 0xFF, (v >> 8) & 0xFF];

  static List<int> _u32(final int v) => [
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ];
}
