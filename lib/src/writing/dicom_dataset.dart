import 'dart:math' as math;
import 'dart:typed_data';

import 'dicom_writer.dart';

/// SOP Class UIDs written by this SDK.
abstract final class DicomSopClass {
  /// Secondary Capture Image Storage.
  static const secondaryCapture = '1.2.840.10008.5.1.4.1.1.7';

  /// Comprehensive SR Storage.
  static const comprehensiveSr = '1.2.840.10008.5.1.4.1.1.88.67';

  /// Explicit VR Little Endian transfer syntax.
  static const explicitLe = '1.2.840.10008.1.2.1';
}

/// Generates `2.25.*` UUID-based OIDs (RFC 9562 §Appendix C style root).
abstract final class DicomUid {
  static final _random = math.Random();

  /// Generates a globally unique UID under the `2.25` UUID root.
  static String generate() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final rand = _random.nextInt(1 << 31);
    // 2.25 + decimal UUID would exceed 64 chars; timestamp+random stays short.
    return '2.25.$micros$rand';
  }
}

/// One encoded dataset element (value field pre-built, even length).
final class DicomDataElement {
  /// Creates an element with an already-encoded [bytes] value field.
  const DicomDataElement({
    required this.group,
    required this.element,
    required this.vr,
    required this.bytes,
  });

  /// Group number (e.g. `0x0010`).
  final int group;

  /// Element number (e.g. `0x0010`).
  final int element;

  /// Two-character Value Representation (e.g. `'PN'`).
  final String vr;

  /// Encoded value field (even length, VR-padded).
  final Uint8List bytes;
}

/// In-memory dataset: SOP identity plus ordered elements.
final class DicomDataset {
  /// Creates a dataset with [elements] and optional SOP identity.
  const DicomDataset({
    this.elements = const [],
    this.sopClassUid,
    this.sopInstanceUid,
  });

  /// Dataset elements (file meta group 0002 excluded — writer-owned).
  final List<DicomDataElement> elements;

  /// SOP Class UID (0008,0016), when set by the builder.
  final String? sopClassUid;

  /// SOP Instance UID (0008,0018), when set by the builder.
  final String? sopInstanceUid;
}

/// Fluent builder for datasets (Secondary Capture, SR, …).
///
/// Only the VRs the SDK writes are exposed; unknown tags go through
/// [custom] without growing this API.
final class DicomDatasetBuilder {
  /// SOP identity (0008,0016 / 0008,0018).
  void sop({required final String classUid, required final String instanceUid}) {
    _sopClassUid = classUid;
    _sopInstanceUid = instanceUid;
    text(0x0008, 0x0016, 'UI', classUid);
    text(0x0008, 0x0018, 'UI', instanceUid);
  }

  /// Patient IE (0010,0010 / 0020 / 0040).
  void patient({final String? name, final String? id, final String? sex}) {
    if (name != null) text(0x0010, 0x0010, 'PN', name);
    if (id != null) text(0x0010, 0x0020, 'LO', id);
    if (sex != null) text(0x0010, 0x0040, 'CS', sex);
  }

  /// Study IE (0020,000D / 0008,1030 …).
  void study({
    required final String studyUid,
    final String? description,
    final String? date,
  }) {
    text(0x0020, 0x000D, 'UI', studyUid);
    if (description != null) text(0x0008, 0x1030, 'LO', description);
    if (date != null) text(0x0008, 0x0020, 'DA', date);
  }

  /// Series IE (0020,000E / 0008,0060 / 0008,103E).
  void series({
    required final String seriesUid,
    final String? modality,
    final String? description,
    final int? number,
  }) {
    text(0x0020, 0x000E, 'UI', seriesUid);
    if (modality != null) text(0x0008, 0x0060, 'CS', modality);
    if (description != null) text(0x0008, 0x103E, 'LO', description);
    if (number != null) text(0x0020, 0x0011, 'IS', '$number');
  }

  /// Image Pixel IE for a single monochrome frame.
  void image({
    required final int rows,
    required final int columns,
    final int bitsAllocated = 8,
    final int? bitsStored,
    final int? highBit,
    final int pixelRepresentation = 0,
    final int samplesPerPixel = 1,
    final String photometric = 'MONOCHROME2',
    final double? rescaleSlope,
    final double? rescaleIntercept,
  }) {
    number(0x0028, 0x0002, 'US', [samplesPerPixel]);
    text(0x0028, 0x0004, 'CS', photometric);
    number(0x0028, 0x0010, 'US', [rows]);
    number(0x0028, 0x0011, 'US', [columns]);
    number(0x0028, 0x0100, 'US', [bitsAllocated]);
    number(0x0028, 0x0101, 'US', [bitsStored ?? bitsAllocated]);
    number(0x0028, 0x0102, 'US', [highBit ?? bitsAllocated - 1]);
    number(0x0028, 0x0103, 'US', [pixelRepresentation]);
    if (rescaleSlope != null) {
      text(0x0028, 0x1053, 'DS', '$rescaleSlope');
    }
    if (rescaleIntercept != null) {
      text(0x0028, 0x1052, 'DS', '$rescaleIntercept');
    }
  }

  /// Pixel Data (7FE0,0010): OB for ≤8-bit, OW otherwise.
  void pixelData(final Uint8List raw, {required final int bitsAllocated}) {
    final vr = bitsAllocated <= 8 ? 'OB' : 'OW';
    _elements.add(
      DicomDataElement(
        group: 0x7FE0,
        element: 0x0010,
        vr: vr,
        bytes: _even(raw, 0x00),
      ),
    );
  }

  /// Content Sequence (0040,A730) from already-built [items].
  void contentSequence(final List<DicomDataset> items) {
    _elements.add(
      DicomDataElement(
        group: 0x0040,
        element: 0xA730,
        vr: 'SQ',
        bytes: DicomWriter.encodeSequenceItems(items),
      ),
    );
  }

  /// Text VR element (PN/LO/SH/CS/UI/DA/TM/DS/IS/AE/UT …).
  void text(final int group, final int element, final String vr, final String value) {
    final pad = vr == 'UI' ? 0x00 : 0x20;
    _elements.add(
      DicomDataElement(
        group: group,
        element: element,
        vr: vr,
        bytes: _even(Uint8List.fromList(_ascii(value)), pad),
      ),
    );
  }

  /// Numeric VR element (US/SS/UL/SL/FL/FD).
  void number(
    final int group,
    final int element,
    final String vr,
    final List<num> values,
  ) {
    final out = BytesBuilder();
    for (final v in values) {
      switch (vr) {
        case 'US':
          out.add(_u16(v.toInt()));
        case 'SS':
          out.add(_u16(v.toInt() & 0xFFFF));
        case 'UL':
          out.add(_u32(v.toInt()));
        case 'SL':
          out.add(_u32(v.toInt() & 0xFFFFFFFF));
        case 'FL':
          out.add(_f32(v.toDouble()));
        case 'FD':
          out.add(_f64(v.toDouble()));
        default:
          throw ArgumentError('Unsupported numeric VR $vr');
      }
    }
    _elements.add(
      DicomDataElement(
        group: group,
        element: element,
        vr: vr,
        bytes: out.toBytes(),
      ),
    );
  }

  /// Raw element for VRs outside the typed helpers.
  void custom(
    final int group,
    final int element,
    final String vr,
    final Uint8List bytes,
  ) {
    _elements.add(
      DicomDataElement(group: group, element: element, vr: vr, bytes: bytes),
    );
  }

  /// Builds the immutable dataset.
  DicomDataset build() => DicomDataset(
        elements: List.unmodifiable(_elements),
        sopClassUid: _sopClassUid,
        sopInstanceUid: _sopInstanceUid,
      );

  final List<DicomDataElement> _elements = [];
  String? _sopClassUid;
  String? _sopInstanceUid;

  static List<int> _ascii(final String s) =>
      [for (final c in s.codeUnits) c <= 255 ? c : 0x3F];

  static Uint8List _even(final Uint8List bytes, final int pad) {
    if (bytes.length.isEven) return bytes;
    return Uint8List.fromList([...bytes, pad]);
  }

  static List<int> _u16(final int v) => [v & 0xFF, (v >> 8) & 0xFF];

  static List<int> _u32(final int v) => [
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ];

  static List<int> _f32(final double v) {
    final data = ByteData(4)..setFloat32(0, v, Endian.little);
    return data.buffer.asUint8List();
  }

  static List<int> _f64(final double v) {
    final data = ByteData(8)..setFloat64(0, v, Endian.little);
    return data.buffer.asUint8List();
  }
}
