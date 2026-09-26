import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_dicom/flutter_dicom.dart';

import 'main.dart';

/// Share tab: image export, DICOM writing, DICOMweb, DIMSE.
///
/// Everything acts on the workstation's current frame or freshly built
/// datasets; result paths and network answers surface inline.
class ShareTab extends StatefulWidget {
  const ShareTab({
    required this.workstation,
    required this.onError,
    super.key,
  });

  final Workstation workstation;
  final ValueChanged<Object> onError;

  @override
  State<ShareTab> createState() => _ShareTabState();
}

class _ShareTabState extends State<ShareTab> {
  String? _lastPath;
  bool _busyExport = false;

  final _webUrl = TextEditingController(text: 'http://127.0.0.1:8080/dicom-web');
  final _webPatient = TextEditingController();
  List<DicomStudy> _webStudies = const [];
  bool _busyWeb = false;

  final _dimseHost = TextEditingController(text: '127.0.0.1');
  final _dimsePort = TextEditingController(text: '104');
  final _dimseAe = TextEditingController(text: 'ANY-SCP');
  DefaultDicomDimseClient? _dimse;
  String _dimseStatus = 'Disconnected';
  List<DicomFindResult> _dimseResults = const [];
  bool _busyDimse = false;

  final _srFinding = TextEditingController(text: 'Nodule in right upper lobe');
  final _srValue = TextEditingController(text: '12.5');

  @override
  void dispose() {
    _webUrl.dispose();
    _webPatient.dispose();
    _dimseHost.dispose();
    _dimsePort.dispose();
    _dimseAe.dispose();
    _srFinding.dispose();
    _srValue.dispose();
    _dimse?.dispose();
    super.dispose();
  }

  Workstation get _w => widget.workstation;

  /// Windowed 8-bit view of the current frame (what you see is what you get).
  Future<({Uint8List gray, int width, int height})> _windowedBytes() async {
    final pixels = _w.controller.pixels!;
    final window = _w.controller.state.window;
    final gray = Uint8List(pixels.width * pixels.height);
    for (var i = 0; i < gray.length; i++) {
      gray[i] =
          (window.apply(pixels.modalityAt(i)) * 255).round().clamp(0, 255);
    }
    return (gray: gray, width: pixels.width, height: pixels.height);
  }

  /// Secondary Capture dataset of the current view.
  Future<DicomDataset> _secondaryCapture() async {
    final view = await _windowedBytes();
    final meta = _w.controller.document?.metadata;
    return (DicomDatasetBuilder()
          ..sop(
            classUid: DicomSopClass.secondaryCapture,
            instanceUid: DicomUid.generate(),
          )
          ..patient(name: meta?.patientName, id: meta?.patientId)
          ..study(studyUid: DicomUid.generate(), description: 'Workstation SC')
          ..series(
            seriesUid: DicomUid.generate(),
            modality: 'OT',
            description: 'Exported view',
          )
          ..image(rows: view.height, columns: view.width)
          ..pixelData(view.gray, bitsAllocated: 8))
        .build();
  }

  Future<void> _exportImage(final DicomExportFormat format) async {
    final pixels = _w.controller.pixels;
    if (pixels == null || _busyExport) return;
    setState(() => _busyExport = true);
    try {
      final bytes = await _w.engine.exporter.export(
        pixels,
        format: format,
        options: const DicomExportOptions(quality: 90),
      );
      final path =
          '${Directory.systemTemp.path}/dicom_export_${DateTime.now().microsecondsSinceEpoch}.${format.name}';
      await File(path).writeAsBytes(bytes);
      if (mounted) setState(() => _lastPath = path);
    } catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => _busyExport = false);
    }
  }

  Future<void> _writeSecondaryCapture() async {
    if (_w.controller.pixels == null) return;
    try {
      final dataset = await _secondaryCapture();
      final path =
          '${Directory.systemTemp.path}/sc_${DateTime.now().microsecondsSinceEpoch}.dcm';
      await DicomWriter.writeFile(dataset, path);
      if (mounted) setState(() => _lastPath = path);
    } catch (e) {
      widget.onError(e);
    }
  }

  Future<void> _writeReport() async {
    try {
      const finding = DicomCode(
        scheme: 'DCM',
        value: '121071',
        meaning: 'Finding',
      );
      final value = double.tryParse(_srValue.text.trim()) ?? 0;
      final report = StructuredReport(
        studyUid: DicomUid.generate(),
        seriesUid: DicomUid.generate(),
        sopUid: DicomUid.generate(),
        patientName: _w.controller.document?.metadata.patientName,
        patientId: _w.controller.document?.metadata.patientId,
        items: [
          SrContainer(
            concept: finding,
            items: [
              SrText(concept: finding, value: _srFinding.text.trim()),
              SrNum(
                concept: finding,
                value: value,
                units: const DicomCode(
                  scheme: 'UCUM',
                  value: 'mm',
                  meaning: 'millimeter',
                ),
              ),
            ],
          ),
        ],
      );
      final path =
          '${Directory.systemTemp.path}/sr_${DateTime.now().microsecondsSinceEpoch}.dcm';
      await DicomWriter.writeFile(report.toDataset(), path);
      if (mounted) setState(() => _lastPath = path);
    } catch (e) {
      widget.onError(e);
    }
  }

  Future<void> _webSearch() async {
    setState(() => _busyWeb = true);
    try {
      final client = HttpDicomWebClient(
        baseUrl: Uri.parse(_webUrl.text.trim()),
      );
      final studies = await client.searchStudies(
        DicomStudyQuery(patientName: _webPatient.text.trim().isEmpty ? null : _webPatient.text.trim()),
      );
      if (mounted) setState(() => _webStudies = studies);
    } catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => _busyWeb = false);
    }
  }

  Future<void> _stowCurrent() async {
    if (_w.controller.pixels == null) return;
    try {
      final dataset = await _secondaryCapture();
      final bytes = DicomWriter.encode(dataset);
      final client = HttpDicomWebClient(
        baseUrl: Uri.parse(_webUrl.text.trim()),
      );
      await client.storeInstance(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('STOW-RS store accepted')),
        );
      }
    } catch (e) {
      widget.onError(e);
    }
  }

  DefaultDicomDimseClient _client() {
    _dimse ??= DefaultDicomDimseClient(parser: _w.engine.parser);
    return _dimse!;
  }

  Future<void> _dimseAssociate() async {
    setState(() => _busyDimse = true);
    try {
      await _client().associate(
        host: _dimseHost.text.trim(),
        port: int.parse(_dimsePort.text.trim()),
        calledAe: _dimseAe.text.trim().isEmpty ? 'ANY-SCP' : _dimseAe.text.trim(),
      );
      if (mounted) setState(() => _dimseStatus = 'Associated');
    } catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => _busyDimse = false);
    }
  }

  Future<void> _dimseEcho() async {
    try {
      final rtt =
          await _client().execute(const DimseEchoCommand()) as Duration;
      if (mounted) {
        setState(() => _dimseStatus = 'Echo OK in ${rtt.inMilliseconds} ms');
      }
    } catch (e) {
      widget.onError(e);
    }
  }

  Future<void> _dimseFind() async {
    setState(() => _busyDimse = true);
    try {
      final results = await _client().execute(
        const DimseFindCommand(DicomStudyQuery()),
      ) as List<DicomFindResult>;
      if (mounted) setState(() => _dimseResults = results);
    } catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => _busyDimse = false);
    }
  }

  Future<void> _dimseStore() async {
    if (_w.controller.pixels == null) return;
    try {
      await _client().execute(DimseStoreCommand(await _secondaryCapture()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('C-STORE accepted')),
        );
      }
    } catch (e) {
      widget.onError(e);
    }
  }

  Future<void> _dimseRelease() async {
    try {
      await _client().release();
    } catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => _dimseStatus = 'Disconnected');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _w.controller.pixels != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_lastPath != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText('Saved: $_lastPath'),
              ),
            ),
          _Card(
            title: 'Image export (current frame)',
            child: Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: !hasImage || _busyExport
                      ? null
                      : () => _exportImage(DicomExportFormat.png),
                  child: const Text('PNG'),
                ),
                FilledButton.tonal(
                  onPressed: !hasImage || _busyExport
                      ? null
                      : () => _exportImage(DicomExportFormat.jpeg),
                  child: const Text('JPEG'),
                ),
                FilledButton.tonal(
                  onPressed: !hasImage || _busyExport
                      ? null
                      : () => _exportImage(DicomExportFormat.tiff),
                  child: const Text('TIFF'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _Card(
            title: 'DICOM writing',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.tonal(
                  onPressed: !hasImage ? null : _writeSecondaryCapture,
                  child: const Text('Write Secondary Capture (.dcm)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _srFinding,
                  decoration: const InputDecoration(
                    labelText: 'Report finding text',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _srValue,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Measurement (mm)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _writeReport,
                  child: const Text('Write Structured Report (.dcm)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _Card(
            title: 'DICOMweb (QIDO / WADO / STOW)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _webUrl,
                  decoration: const InputDecoration(
                    labelText: 'Service root URL',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _webPatient,
                  decoration: const InputDecoration(
                    labelText: 'PatientName filter (optional)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _busyWeb ? null : _webSearch,
                      child: Text(_busyWeb ? 'Searching…' : 'Search studies'),
                    ),
                    FilledButton.tonal(
                      onPressed: !hasImage ? null : _stowCurrent,
                      child: const Text('STOW current view'),
                    ),
                  ],
                ),
                for (final s in _webStudies)
                  ListTile(
                    dense: true,
                    title: Text(s.patientName ?? 'Anonymous'),
                    subtitle: Text(s.studyUid),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _Card(
            title: 'DIMSE / PACS ($_dimseStatus)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _dimseHost,
                        decoration: const InputDecoration(
                          labelText: 'Host',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _dimsePort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _dimseAe,
                        decoration: const InputDecoration(
                          labelText: 'Called AE',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _busyDimse ? null : _dimseAssociate,
                      child: const Text('Associate'),
                    ),
                    FilledButton.tonal(
                      onPressed: _dimseEcho,
                      child: const Text('C-ECHO'),
                    ),
                    FilledButton.tonal(
                      onPressed: _busyDimse ? null : _dimseFind,
                      child: Text(_busyDimse ? 'Finding…' : 'C-FIND studies'),
                    ),
                    FilledButton.tonal(
                      onPressed: !hasImage ? null : _dimseStore,
                      child: const Text('C-STORE view'),
                    ),
                    OutlinedButton(
                      onPressed: _dimseRelease,
                      child: const Text('Release'),
                    ),
                  ],
                ),
                for (final r in _dimseResults)
                  ListTile(
                    dense: true,
                    title: Text(r.patientName ?? 'Anonymous'),
                    subtitle: Text(
                      '${r.studyUid} · ${r.modality ?? '—'}',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
