import 'dart:typed_data';

import '../writing/dicom_dataset.dart';
import 'dicom_network.dart';

/// DICOM PS3.8 PDU codec + PS3.7 command datasets (implicit LE).
///
/// Covers association (RQ/AC/RJ), release, abort, and P-DATA framing.
/// Command datasets use implicit LE with a group-0000 VR table; clinical
/// datasets stay explicit LE via [DicomDatasetBuilder]/[DicomWriter].
abstract final class DimsePdu {
  /// A-ASSOCIATE-RQ PDU type.
  static const assocRq = 0x01;

  /// A-ASSOCIATE-AC PDU type.
  static const assocAc = 0x02;

  /// A-ASSOCIATE-RJ PDU type.
  static const assocRj = 0x03;

  /// P-DATA-TF PDU type.
  static const pData = 0x04;

  /// A-RELEASE-RQ PDU type.
  static const releaseRq = 0x05;

  /// A-RELEASE-RP PDU type.
  static const releaseRp = 0x06;

  /// A-ABORT PDU type.
  static const abort = 0x07;

  /// Verification SOP Class (C-ECHO).
  static const verificationUid = '1.2.840.10008.1.2';

  /// Study Root FIND SOP Class.
  static const studyRootFindUid = '1.2.840.10008.5.1.4.1.2.2.1';

  /// Application context name (DICOM 3.1.1.1).
  static const applicationContext = '1.2.840.10008.3.1.1.1';

  /// Explicit LE transfer syntax proposed for every presentation context.
  static const transferSyntax = '1.2.840.10008.1.2.1';

  /// C-STORE command field.
  static const cmdStore = 0x0001;

  /// C-FIND command field.
  static const cmdFind = 0x0020;

  /// C-ECHO command field.
  static const cmdEcho = 0x0030;

  /// Success status.
  static const statusSuccess = 0x0000;

  /// Pending status (more identifiers follow).
  static const statusPending = 0xFF00;

  /// Pending-with-warning status.
  static const statusPendingWarning = 0xFF01;

  /// Encodes an A-ASSOCIATE-RQ for [abstractSyntaxes] (one PC each, odd IDs).
  static Uint8List encodeAssociateRq({
    required final String callingAe,
    required final String calledAe,
    required final List<String> abstractSyntaxes,
    final int maxPduLength = 16384,
  }) {
    final variable = BytesBuilder();
    _item(variable, 0x10, _ascii(applicationContext)); // app context
    var pcId = 1;
    for (final sop in abstractSyntaxes) {
      final pc = BytesBuilder();
      pc.addByte(pcId);
      pc.add([0x00, 0x00, 0x00]); // reserved
      _subItem(pc, 0x30, _ascii(sop)); // abstract syntax
      _subItem(pc, 0x40, _ascii(transferSyntax)); // transfer syntax
      _item(variable, 0x20, pc.toBytes());
      pcId += 2;
    }
    final user = BytesBuilder();
    user.add([0x51, 0x00, 0x04, 0x00]); // max PDU length
    user.add(_u32be(maxPduLength));
    _subItem(user, 0x52, _ascii('2.25.2882753235109249')); // impl UID
    _subItem(user, 0x55, _ascii('FLUTTER_DICOM_020')); // impl version
    _item(variable, 0x50, user.toBytes());
    final variableBytes = variable.toBytes();

    final out = BytesBuilder();
    // Rebuild in wire order: called AE first, then calling AE.
    out.addByte(assocRq);
    out.addByte(0x00);
    out.add(_u32be(68 + variableBytes.length));
    out.add(_u16(0x0001));
    out.add([0x00, 0x00]);
    out.add(_ae(calledAe));
    out.add(_ae(callingAe));
    out.add(Uint8List(32)); // reserved
    out.add(variableBytes);
    return out.toBytes();
  }

  /// Decodes an A-ASSOCIATE-AC body into accepted PCs and max PDU length.
  static DimseAssocAc decodeAssociateAc(final Uint8List body) {
    // body skips the 6-byte PDU header; starts at protocol version.
    var i = 2 + 2 + 16 + 16 + 32; // version + reserved + AEs + reserved
    final accepted = <int, String>{};
    var maxPdu = 16384;
    String? rejectedReason;
    while (i + 4 <= body.length) {
      final type = body[i];
      final len = (body[i + 2] << 8) | body[i + 3];
      final value = body.sublist(i + 4, i + 4 + len);
      if (type == 0x21 && len >= 4) {
        final pcId = value[0];
        final result = value[2];
        if (result == 0 && value.length > 4) {
          // First transfer-syntax sub-item holds the accepted TS.
          var j = 4;
          while (j + 4 <= value.length) {
            final st = value[j];
            final sl = (value[j + 2] << 8) | value[j + 3];
            if (st == 0x40) {
              accepted[pcId] = ascii(value.sublist(j + 4, j + 4 + sl));
              break;
            }
            j += 4 + sl;
          }
        } else if (result != 0) {
          rejectedReason = 'PC $pcId rejected (result $result)';
        }
      } else if (type == 0x50) {
        var j = 0;
        while (j + 4 <= value.length) {
          final st = value[j];
          final sl = (value[j + 2] << 8) | value[j + 3];
          if (st == 0x51 && sl == 4) {
            maxPdu = (value[j + 4] << 24) |
                (value[j + 5] << 16) |
                (value[j + 6] << 8) |
                value[j + 7];
          }
          j += 4 + sl;
        }
      }
      i += 4 + len;
    }
    return DimseAssocAc(
      acceptedTransferSyntaxes: accepted,
      maxPduLength: maxPdu,
      rejectionReason: accepted.isEmpty ? rejectedReason : null,
    );
  }

  /// Encodes a P-DATA-TF PDU with a single PDV (caller fragments at max PDU).
  static Uint8List encodePData({
    required final int presentationContextId,
    required final bool isCommand,
    required final bool isLast,
    required final Uint8List data,
  }) {
    final out = BytesBuilder();
    out.addByte(pData);
    out.addByte(0x00);
    out.add(_u32be(6 + data.length));
    out.add(_u32be(2 + data.length)); // PDV length: pcId + flags + data
    out.addByte(presentationContextId);
    out.addByte((isCommand ? 0x01 : 0x00) | (isLast ? 0x02 : 0x00));
    out.add(data);
    return out.toBytes();
  }

  /// Encodes a RELEASE-RQ / RELEASE-RP PDU.
  static Uint8List encodeRelease(final bool request) {
    return Uint8List.fromList([
      request ? releaseRq : releaseRp,
      0x00,
      0x00,
      0x00,
      0x00,
      0x04,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);
  }

  /// Encodes an A-ABORT PDU.
  static Uint8List encodeAbort() {
    return Uint8List.fromList(
        [abort, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00]);
  }

  /// Builds a C-ECHO-RQ command dataset (implicit LE).
  static Uint8List echoCommand(final int messageId) => _command({
        0x00020002: verificationUid,
        0x00000100: cmdEcho,
        0x00000110: messageId,
        0x00000800: 0x0101,
      });

  /// Builds a C-STORE-RQ command dataset (implicit LE).
  static Uint8List storeCommand(
    final int messageId, {
    required final String sopClassUid,
    required final String sopInstanceUid,
  }) =>
      _command({
        0x00020002: sopClassUid,
        0x00000100: cmdStore,
        0x00000110: messageId,
        0x00000700: 0x0002, // medium priority
        0x00000800: 0x0001, // data set present
        0x00001000: sopInstanceUid,
      });

  /// Builds a C-FIND-RQ command dataset (implicit LE).
  static Uint8List findCommand(final int messageId) => _command({
        0x00020002: studyRootFindUid,
        0x00000100: cmdFind,
        0x00000110: messageId,
        0x00000700: 0x0002,
        0x00000800: 0x0001,
      });

  /// Builds a study-level C-FIND identifier (explicit LE, empty = universal).
  static Uint8List findIdentifier(final DicomStudyQuery query) {
    final b = DicomDatasetBuilder()
      ..text(0x0008, 0x0052, 'CS', 'STUDY')
      ..text(0x0010, 0x0010, 'PN', query.patientName ?? '')
      ..text(0x0020, 0x000D, 'UI', '')
      ..text(0x0008, 0x0020, 'DA', query.studyDate ?? '')
      ..text(0x0008, 0x0060, 'CS', query.modality ?? '');
    return _explicitElements(b.build().elements);
  }

  /// Parses a command group (implicit LE) into tag-keyed values.
  static Map<int, Object> decodeCommandGroup(final Uint8List bytes) {
    final out = <int, Object>{};
    var i = 0;
    while (i + 8 <= bytes.length) {
      final group = bytes[i] | (bytes[i + 1] << 8);
      final element = bytes[i + 2] | (bytes[i + 3] << 8);
      final len = bytes[i + 4] |
          (bytes[i + 5] << 8) |
          (bytes[i + 6] << 16) |
          (bytes[i + 7] << 24);
      final value = bytes.sublist(i + 8, i + 8 + len);
      final key = (group << 16) | element;
      out[key] = _commandValue(group, element, value);
      i += 8 + len;
    }
    return out;
  }

  // -- internals ----------------------------------------------------------

  static Object _commandValue(
      final int group, final int element, final Uint8List value) {
    if (group != 0x0000) return value;
    return switch (element) {
      0x0000 => (value[0] | (value[1] << 8) | (value[2] << 16) | (value[3] << 24)),
      0x0002 || 0x0003 || 0x1000 || 0x1001 => ascii(value).trim(),
      _ => value[0] | (value[1] << 8),
    };
  }

  /// Encodes command elements (implicit LE) with a leading group length.
  static Uint8List _command(final Map<int, Object> fields) {
    final body = BytesBuilder();
    final keys = fields.keys.toList()..sort();
    for (final key in keys) {
      final group = (key >> 16) & 0xFFFF;
      final element = key & 0xFFFF;
      final v = fields[key]!;
      body.add(_u16(group));
      body.add(_u16(element));
      if (v is String) {
        // Command strings here are UI: NUL-padded to even length.
        final bytes = _even(_ascii(v), 0x00);
        body.add(_u32(bytes.length));
        body.add(bytes);
      } else {
        body.add(_u32(2));
        body.add(_u16((v as int) & 0xFFFF));
      }
    }
    final bodyBytes = body.toBytes();
    final out = BytesBuilder();
    out.add(_u16(0x0000));
    out.add(_u16(0x0000));
    out.add(_u32(4));
    out.add(_u32(bodyBytes.length));
    out.add(bodyBytes);
    return out.toBytes();
  }

  /// Encodes explicit-LE elements (identifier datasets).
  static Uint8List _explicitElements(final List<DicomDataElement> elements) {
    final sorted = List.of(elements)
      ..sort((final a, final b) {
        final g = a.group.compareTo(b.group);
        return g != 0 ? g : a.element.compareTo(b.element);
      });
    final out = BytesBuilder();
    for (final e in sorted) {
      out.add(_u16(e.group));
      out.add(_u16(e.element));
      out.add(e.vr.codeUnits);
      if (e.vr == 'SQ' ||
          e.vr == 'OB' ||
          e.vr == 'OW' ||
          e.vr == 'UT' ||
          e.vr == 'UN') {
        out.add([0x00, 0x00]);
        out.add(_u32(e.bytes.length));
      } else {
        out.add(_u16(e.bytes.length));
      }
      out.add(e.bytes);
    }
    return out.toBytes();
  }

  static void _item(final BytesBuilder out, final int type, final List<int> v) {
    out.addByte(type);
    out.addByte(0x00);
    out.add([(v.length >> 8) & 0xFF, v.length & 0xFF]);
    out.add(v);
  }

  static void _subItem(
      final BytesBuilder out, final int type, final List<int> v) {
    _item(out, type, v);
  }

  static List<int> _ae(final String ae) {
    final bytes = _ascii(ae.length > 16 ? ae.substring(0, 16) : ae);
    return [...bytes, ...List.filled(16 - bytes.length, 0x20)];
  }

  static List<int> _ascii(final String s) =>
      [for (final c in s.codeUnits) c <= 255 ? c : 0x3F];

  /// Decodes padded ASCII (AE titles, transfer syntax names).
  static String ascii(final List<int> bytes) =>
      String.fromCharCodes(bytes).trim().replaceAll('\x00', '');

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

  /// Big-endian u32 for PDU / PDV framing (PS3.8 is network order).
  static List<int> _u32be(final int v) => [
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];
}

/// Parsed A-ASSOCIATE-AC outcome.
final class DimseAssocAc {
  /// Creates an association-accept outcome.
  const DimseAssocAc({
    required this.acceptedTransferSyntaxes,
    required this.maxPduLength,
    this.rejectionReason,
  });

  /// Accepted transfer syntax per presentation context ID.
  final Map<int, String> acceptedTransferSyntaxes;

  /// Remote max PDU length for our sends.
  final int maxPduLength;

  /// Set when nothing was accepted.
  final String? rejectionReason;
}
