import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../application/ports/dicom_parser.dart';
import '../domain/dicom_source.dart';
import '../domain/dicom_tag_id.dart';
import '../errors/dicom_exception.dart';
import '../writing/dicom_dataset.dart';
import '../writing/dicom_writer.dart';
import 'dicom_network.dart';
import 'dimse_pdu.dart';

/// Association configuration for [DefaultDicomDimseClient].
final class DimseAssociationConfig {
  /// Creates association tuning.
  const DimseAssociationConfig({
    this.callingAe = 'FLUTTER_DICOM',
    this.calledAe = 'ANY-SCP',
    this.maxPduLength = 16384,
    this.connectTimeout = const Duration(seconds: 10),
    this.responseTimeout = const Duration(seconds: 30),
    this.storageClasses = const [
      DicomSopClass.secondaryCapture,
      DicomSopClass.comprehensiveSr,
    ],
  });

  /// Our AE title (max 16 chars).
  final String callingAe;

  /// Remote AE title.
  final String calledAe;

  /// Max PDU we receive (also caps our fragment size).
  final int maxPduLength;

  /// TCP connect timeout.
  final Duration connectTimeout;

  /// Per-response timeout.
  final Duration responseTimeout;

  /// Storage SOP classes proposed besides Verification + FIND.
  final List<String> storageClasses;
}

/// DIMSE client over TCP: association state machine + Echo/Store/Find.
///
/// Explicit LE only (M7 constraint): every presentation context proposes
/// [DimsePdu.transferSyntax], and datasets encode through [DicomWriter].
/// Move/Get stay typed ([DimseMoveCommand]/[DimseGetCommand]) for a future
/// inbound Storage SCP and fail fast instead of half-working.
final class DefaultDicomDimseClient implements DicomDimseClient {
  /// Creates a client, optionally with a [parser] for FIND identifiers.
  DefaultDicomDimseClient({
    final DicomParser? parser,
    this.config = const DimseAssociationConfig(),
  }) : _parser = parser;

  /// Association tuning.
  final DimseAssociationConfig config;

  final DicomParser? _parser;
  final StreamController<DimseAssocState> _states =
      StreamController<DimseAssocState>.broadcast();

  DimseAssocState _state = DimseAssocState.disconnected;
  Socket? _socket;
  StreamIterator<Uint8List>? _reader;
  Uint8List _pending = Uint8List(0);
  final Map<int, String> _pcs = {}; // pcId → abstract syntax
  int _maxPdu = 16384;
  int _messageId = 0;

  @override
  DimseAssocState get state => _state;

  @override
  Stream<DimseAssocState> get states => _states.stream;

  @override
  Future<void> associate({
    required final String host,
    required final int port,
    final String callingAe = 'FLUTTER_DICOM',
    final String calledAe = 'ANY-SCP',
  }) async {
    if (_state != DimseAssocState.disconnected) {
      throw const DicomNetworkException('Already associated or associating');
    }
    _setState(DimseAssocState.associating);
    try {
      final abstractSyntaxes = [
        DimsePdu.verificationUid,
        DimsePdu.studyRootFindUid,
        ...config.storageClasses,
      ];
      // Socket lifetime is owned by the client
      // (_close/release/abort/dispose); it must survive associate().
      // ignore: close_sinks
      final socket = await Socket.connect(
        host,
        port,
        timeout: config.connectTimeout,
      );
      _socket = socket;
      _reader = StreamIterator(socket);
      _pending = Uint8List(0);
      socket.add(
        DimsePdu.encodeAssociateRq(
          callingAe: callingAe,
          calledAe: calledAe,
          abstractSyntaxes: abstractSyntaxes,
          maxPduLength: config.maxPduLength,
        ),
      );
      await socket.flush();
      final pdu = await _readPdu();
      if (pdu.type == DimsePdu.assocRj) {
        throw const DicomNetworkException('Association rejected by remote AE');
      }
      if (pdu.type != DimsePdu.assocAc) {
        throw DicomNetworkException(
          'Expected A-ASSOCIATE-AC, got PDU 0x${pdu.type.toRadixString(16)}',
        );
      }
      final ac = DimsePdu.decodeAssociateAc(pdu.body);
      if (ac.acceptedTransferSyntaxes.isEmpty) {
        throw DicomNetworkException(
          'Association rejected (${ac.rejectionReason ?? 'no PCs accepted'})',
        );
      }
      _pcs.clear();
      var pcId = 1;
      for (final sop in abstractSyntaxes) {
        final ts = ac.acceptedTransferSyntaxes[pcId];
        if (ts != null) {
          if (ts != DimsePdu.transferSyntax) {
            throw DicomNetworkException(
              'SCP accepted $sop with $ts; M7 supports Explicit LE only',
            );
          }
          _pcs[pcId] = sop;
        }
        pcId += 2;
      }
      _maxPdu = ac.maxPduLength;
      _setState(DimseAssocState.associated);
    } catch (e) {
      await _close();
      _setState(DimseAssocState.disconnected);
      if (e is DicomException) rethrow;
      throw DicomNetworkException('Association failed ($e)');
    }
  }

  @override
  Future<Object?> execute(final DimseCommand command) async {
    _requireAssociated();
    switch (command) {
      case DimseEchoCommand():
        return _echo();
      case DimseStoreCommand(:final dataset):
        await _store(dataset);
        return null;
      case DimseFindCommand(:final query):
        return _find(query);
      case DimseMoveCommand():
        throw UnimplementedError(
          'C-MOVE needs an inbound Storage SCP (typed for a later milestone)',
        );
      case DimseGetCommand():
        throw UnimplementedError(
          'C-GET needs an inbound Storage SCP (typed for a later milestone)',
        );
    }
  }

  @override
  Future<void> release() async {
    if (_state == DimseAssocState.disconnected) return;
    _setState(DimseAssocState.releasing);
    try {
      _socket?.add(DimsePdu.encodeRelease(true));
      await _socket?.flush();
      final pdu = await _readPdu();
      if (pdu.type != DimsePdu.releaseRp) {
        throw DicomNetworkException(
          'Expected A-RELEASE-RP, got PDU 0x${pdu.type.toRadixString(16)}',
        );
      }
    } finally {
      await _close();
      _setState(DimseAssocState.disconnected);
    }
  }

  @override
  Future<void> abort() async {
    try {
      _socket?.add(DimsePdu.encodeAbort());
      await _socket?.flush();
    } finally {
      await _close();
      _setState(DimseAssocState.disconnected);
    }
  }

  @override
  void dispose() {
    unawaited(_close());
    unawaited(_states.close());
  }

  // -- commands ------------------------------------------------------------

  /// C-ECHO round trip; returns the round-trip time.
  Future<Duration> _echo() async {
    final pc = _pcFor(DimsePdu.verificationUid);
    final stopwatch = Stopwatch()..start();
    final msgId = _nextMessageId();
    _sendCommand(pc, DimsePdu.echoCommand(msgId), null);
    final response = await _readCommandResponse();
    _checkStatus(response, 'C-ECHO', msgId: msgId);
    stopwatch.stop();
    return stopwatch.elapsed;
  }

  /// C-STORE of [dataset]; throws on non-success status.
  Future<void> _store(final DicomDataset dataset) async {
    final sopClass =
        dataset.sopClassUid ?? DicomSopClass.secondaryCapture;
    final sopInstance = dataset.sopInstanceUid ?? DicomUid.generate();
    final pc = _pcFor(sopClass);
    final msgId = _nextMessageId();
    _sendCommand(
      pc,
      DimsePdu.storeCommand(
        msgId,
        sopClassUid: sopClass,
        sopInstanceUid: sopInstance,
      ),
      DicomWriter.encodeElements(dataset.elements),
    );
    final response = await _readCommandResponse();
    _checkStatus(response, 'C-STORE', msgId: msgId);
  }

  /// C-FIND collecting pending identifiers into [DicomFindResult]s.
  Future<List<DicomFindResult>> _find(final DicomStudyQuery query) async {
    final parser = _parser;
    if (parser == null) {
      throw const DicomConfigurationException(
        'C-FIND needs a DicomParser (pass one to DefaultDicomDimseClient)',
      );
    }
    final pc = _pcFor(DimsePdu.studyRootFindUid);
    final msgId = _nextMessageId();
    _sendCommand(pc, DimsePdu.findCommand(msgId), DimsePdu.findIdentifier(query));
    final results = <DicomFindResult>[];
    while (true) {
      final response = await _readCommandResponse();
      final status = _statusOf(response, 'C-FIND', msgId: msgId);
      if (status == DimsePdu.statusSuccess) break;
      if (status != DimsePdu.statusPending &&
          status != DimsePdu.statusPendingWarning) {
        throw DicomNetworkException(
          'C-FIND failed with status 0x${status.toRadixString(16)}',
        );
      }
      final identifier = await _readDataset();
      results.add(await _mapIdentifier(parser, identifier));
    }
    return results;
  }

  /// Wraps bare identifier bytes in a file envelope so the shared parser
  /// (which reads files, not bare datasets) can extract the matched keys.
  Future<DicomFindResult> _mapIdentifier(
    final DicomParser parser,
    final Uint8List identifier,
  ) async {
    final head = DicomWriter.encode(
      (DicomDatasetBuilder()
            ..sop(
              classUid: DimsePdu.studyRootFindUid,
              instanceUid: DicomUid.generate(),
            ))
          .build(),
    );
    final wrapped = Uint8List.fromList([...head, ...identifier]);
    final doc = await parser.parse(DicomSource.bytes(wrapped));
    final meta = doc.metadata;
    return DicomFindResult(
      studyUid: meta.tag<String>(DicomTagId.studyInstanceUid) ?? '',
      patientName: meta.patientName,
      studyDate: meta.bestDate,
      modality: meta.modality?.name,
    );
  }

  // -- framing --------------------------------------------------------------

  void _requireAssociated() {
    if (_state != DimseAssocState.associated || _socket == null) {
      throw const DicomNetworkException('Not associated (call associate first)');
    }
  }

  int _pcFor(final String abstractSyntax) {
    for (final entry in _pcs.entries) {
      if (entry.value == abstractSyntax) return entry.key;
    }
    throw DicomNetworkException(
      'No accepted presentation context for $abstractSyntax',
    );
  }

  int _nextMessageId() {
    _messageId = (_messageId % 65535) + 1;
    return _messageId;
  }

  /// Sends command + optional dataset, fragmenting at the negotiated max PDU.
  void _sendCommand(
    final int pcId,
    final Uint8List command,
    final Uint8List? dataset,
  ) {
    final commandChunks = _fragments(command);
    for (var i = 0; i < commandChunks.length; i++) {
      _socket!.add(
        DimsePdu.encodePData(
          presentationContextId: pcId,
          isCommand: true,
          // A command message is complete on its own; a following dataset
          // travels as separate data PDVs keyed by the command flag.
          isLast: i == commandChunks.length - 1,
          data: commandChunks[i],
        ),
      );
    }
    if (dataset != null) {
      final chunks = _fragments(dataset);
      for (var i = 0; i < chunks.length; i++) {
        _socket!.add(
          DimsePdu.encodePData(
            presentationContextId: pcId,
            isCommand: false,
            isLast: i == chunks.length - 1,
            data: chunks[i],
          ),
        );
      }
    }
    unawaited(_socket!.flush());
  }

  List<Uint8List> _fragments(final Uint8List bytes) {
    final maxChunk = _maxPdu - 12; // PDU header (6) + PDV header (6)
    final out = <Uint8List>[];
    for (var i = 0; i < bytes.length; i += maxChunk) {
      final end = (i + maxChunk).clamp(0, bytes.length);
      out.add(Uint8List.fromList(bytes.sublist(i, end)));
    }
    if (out.isEmpty) out.add(Uint8List(0));
    return out;
  }

  /// Reads one command response (fragments reassembled).
  Future<Map<int, Object>> _readCommandResponse() async {
    final data = BytesBuilder();
    while (true) {
      final pdu = await _readPdu();
      if (pdu.type != DimsePdu.pData) {
        throw DicomNetworkException(
          'Expected P-DATA-TF, got PDU 0x${pdu.type.toRadixString(16)}',
        );
      }
      final pdv = _pdv(pdu.body);
      if (!pdv.isCommand) {
        throw const DicomNetworkException(
          'Expected command PDV in response',
        );
      }
      data.add(pdv.data);
      if (pdv.isLast) break;
    }
    return DimsePdu.decodeCommandGroup(data.toBytes());
  }

  /// Reads one dataset response (fragments reassembled).
  Future<Uint8List> _readDataset() async {
    final data = BytesBuilder();
    while (true) {
      final pdu = await _readPdu();
      if (pdu.type != DimsePdu.pData) {
        throw DicomNetworkException(
          'Expected P-DATA-TF, got PDU 0x${pdu.type.toRadixString(16)}',
        );
      }
      final pdv = _pdv(pdu.body);
      if (pdv.isCommand) {
        throw const DicomNetworkException(
          'Expected data PDV for pending identifier',
        );
      }
      data.add(pdv.data);
      if (pdv.isLast) break;
    }
    return data.toBytes();
  }

  _Pdv _pdv(final Uint8List body) {
    if (body.length < 6) {
      throw const DicomNetworkException('Truncated PDV header');
    }
    final len = (body[0] << 24) | (body[1] << 16) | (body[2] << 8) | body[3];
    final pcId = body[4];
    final flags = body[5];
    final data = body.sublist(6, 4 + len);
    if (data.length != len - 2) {
      throw const DicomNetworkException('Truncated PDV value');
    }
    return _Pdv(
      presentationContextId: pcId,
      isCommand: (flags & 0x01) != 0,
      isLast: (flags & 0x02) != 0,
      data: Uint8List.fromList(data),
    );
  }

  int _statusOf(
    final Map<int, Object> command, final String op, {required final int msgId,
  }) {
    final gotId = command[0x00000110];
    if (gotId is int && gotId != msgId) {
      throw DicomNetworkException('$op response message ID mismatch');
    }
    final status = command[0x00000900];
    if (status is! int) {
      throw DicomNetworkException('$op response carries no status');
    }
    return status;
  }

  void _checkStatus(
    final Map<int, Object> command, final String op, {required final int msgId,
  }) {
    final status = _statusOf(command, op, msgId: msgId);
    if (status != DimsePdu.statusSuccess) {
      throw DicomNetworkException(
        '$op failed with status 0x${status.toRadixString(16)}',
      );
    }
  }

  Future<_Pdu> _readPdu() async {
    final header = await _readExactly(6);
    final type = header[0];
    final len = (header[2] << 24) |
        (header[3] << 16) |
        (header[4] << 8) |
        header[5];
    if (len < 0 || len > 16 * 1024 * 1024) {
      throw const DicomNetworkException('Absurd PDU length');
    }
    final body = await _readExactly(len);
    return _Pdu(type, body);
  }

  Future<Uint8List> _readExactly(final int n) async {
    final out = BytesBuilder();
    var need = n;
    if (_pending.isNotEmpty) {
      final take = need < _pending.length ? need : _pending.length;
      out.add(_pending.sublist(0, take));
      _pending = Uint8List.fromList(_pending.sublist(take));
      need -= take;
    }
    final reader = _reader;
    if (reader == null) throw const DicomNetworkException('Not connected');
    while (need > 0) {
      bool hasMore;
      try {
        hasMore = await reader.moveNext().timeout(config.responseTimeout);
      } on TimeoutException {
        throw const DicomNetworkException('Timed out waiting for PDU');
      }
      if (!hasMore) throw const DicomNetworkException('Connection closed');
      final chunk = reader.current;
      if (chunk.length >= need) {
        out.add(chunk.sublist(0, need));
        _pending = Uint8List.fromList(chunk.sublist(need));
        need = 0;
      } else {
        out.add(chunk);
        need -= chunk.length;
      }
    }
    return out.toBytes();
  }

  void _setState(final DimseAssocState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> _close() async {
    try {
      await _reader?.cancel();
    } catch (_) {}
    _reader = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _pcs.clear();
    _pending = Uint8List(0);
  }
}

/// Decoded PDU (type + body after the 6-byte header).
final class _Pdu {
  const _Pdu(this.type, this.body);

  /// PDU type byte.
  final int type;

  /// PDU body bytes.
  final Uint8List body;
}

/// Decoded presentation-data-value fragment.
final class _Pdv {
  const _Pdv({
    required this.presentationContextId,
    required this.isCommand,
    required this.isLast,
    required this.data,
  });

  /// Presentation context the fragment belongs to.
  final int presentationContextId;

  /// Command (true) vs data (false) fragment.
  final bool isCommand;

  /// Last fragment of this command / dataset.
  final bool isLast;

  /// Fragment payload.
  final Uint8List data;
}
