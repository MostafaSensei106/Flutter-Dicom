import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dicom/flutter_dicom.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The engine initializes the native bridge — no RustLib handling here.
  await DicomEngine.create();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter DICOM Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.purple),
      home: const DicomDemoScreen(),
    );
  }
}

class DicomDemoScreen extends StatefulWidget {
  const DicomDemoScreen({super.key});

  @override
  State<DicomDemoScreen> createState() => _DicomDemoScreenState();
}

class _DicomDemoScreenState extends State<DicomDemoScreen> {
  late final DefaultDicomViewerController _controller =
      DefaultDicomViewerController();
  late final DefaultDicomCineController _cine = DefaultDicomCineController(
    onFrame: (final index) => _controller.setFrame(index),
  );

  RoiStatistics? _roiStats;
  bool _busyRoi = false;
  double _fps = 24;

  @override
  void dispose() {
    _cine.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _showError(final Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error loading DICOM: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  /// Opens a single file through the file-system path source.
  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || files.single.path == null) return;
    try {
      await _controller.load(DicomSource.file(files.single.path!));
      _clearAnalysis();
    } catch (e) {
      _showError(e);
    }
  }

  /// Opens a single file through the in-memory bytes source (Web / PACS path).
  Future<void> _pickFileAsBytes() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return;
    try {
      final picked = files.single;
      final bytes = await picked.xFile.readAsBytes();
      await _controller.load(DicomSource.bytes(bytes));
      _clearAnalysis();
    } catch (e) {
      _showError(e);
    }
  }

  /// Opens a folder of slices as one scrub-able series document.
  Future<void> _pickSeriesFolder() async {
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null) return;
    try {
      final paths = Directory(dirPath)
          .listSync()
          .whereType<File>()
          .map((final f) => f.path)
          .where((final p) => p.toLowerCase().endsWith('.dcm'))
          .toList()
        ..sort();
      if (paths.isEmpty) {
        throw const DicomProcessingException('No .dcm files found');
      }
      await _controller.load(DicomSource.files(paths));
      _clearAnalysis();
    } catch (e) {
      _showError(e);
    }
  }

  void _clearAnalysis() {
    setState(() => _roiStats = null);
  }

  /// Analyzes the central quarter as an ROI (min / max / mean / std-dev).
  Future<void> _analyzeCenterRoi() async {
    final pixels = _controller.pixels;
    if (pixels == null) return;
    setState(() => _busyRoi = true);
    try {
      final roi = DicomRoi(
        DicomRect(
          pixels.width / 4,
          pixels.height / 4,
          pixels.width / 2,
          pixels.height / 2,
        ),
      );
      final stats = await roi.analyze(pixels);
      if (mounted) setState(() => _roiStats = stats);
    } finally {
      if (mounted) setState(() => _busyRoi = false);
    }
  }

  /// Exports the current windowed view as a grayscale PNG to temp storage.
  Future<void> _exportPng() async {
    final pixels = _controller.pixels;
    if (pixels == null || !mounted) return;
    try {
      final png = await const PngDicomExporter().exportWindowed(
        pixels,
        _controller.state.window,
      );
      final path =
          '${Directory.systemTemp.path}/dicom_frame_${_controller.state.currentFrame}.png';
      await File(path).writeAsBytes(png);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exported PNG: $path')));
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter DICOM'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Open file',
            onPressed: _pickFile,
            icon: const Icon(Icons.file_open_rounded),
          ),
          IconButton(
            tooltip: 'Open as bytes',
            onPressed: _pickFileAsBytes,
            icon: const Icon(Icons.memory_rounded),
          ),
          IconButton(
            tooltip: 'Open series folder',
            onPressed: _pickSeriesFolder,
            icon: const Icon(Icons.folder_open_rounded),
          ),
          IconButton(
            tooltip: 'Reset viewer',
            onPressed: () => _controller.reset(),
            icon: const Icon(Icons.restore_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<DicomViewerState>(
        stream: _controller.states,
        initialData: _controller.state,
        builder: (final context, final snapshot) {
          final state = snapshot.data ?? _controller.state;
          final ready = state.status is DicomViewerReady;
          return Column(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    DicomViewer(
                      controller: _controller,
                      overlays: const [
                        ScaleBarOverlay(),
                        OrientationOverlay(),
                        PixelProbeOverlay(),
                      ],
                    ),
                    if (ready)
                      Positioned(
                        bottom: 12,
                        left: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _controller.document?.metadata.patientName ??
                                  'Anonymous',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${state.currentFrame + 1} / ${state.frameCount}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (ready)
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (state.frameCount > 1) ...[
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  _cine.playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                onPressed: () {
                                  if (_cine.playing) {
                                    _cine.pause();
                                  } else {
                                    _cine.play(
                                      frameCount: state.frameCount,
                                    );
                                  }
                                  setState(() {});
                                },
                              ),
                              Expanded(
                                child: Slider(
                                  value: state.currentFrame.toDouble().clamp(
                                    0,
                                    (state.frameCount - 1).toDouble(),
                                  ),
                                  min: 0,
                                  max: (state.frameCount - 1).toDouble(),
                                  divisions: state.frameCount - 1,
                                  onChanged: (final v) =>
                                      _controller.setFrame(v.toInt()),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Text('FPS'),
                              Expanded(
                                child: Slider(
                                  value: _fps,
                                  min: 1,
                                  max: 60,
                                  divisions: 59,
                                  label: _fps.toStringAsFixed(0),
                                  onChanged: (final v) {
                                    setState(() => _fps = v);
                                    _cine.setFps(v);
                                  },
                                ),
                              ),
                              Text(_fps.toStringAsFixed(0)),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final preset in DicomWindowPreset.all)
                              ActionChip(
                                label: Text(preset.label ?? ''),
                                onPressed: () =>
                                    _controller.setWindow(preset),
                              ),
                            ActionChip(
                              label: Text(
                                state.invert ? 'Uninvert' : 'Invert',
                              ),
                              onPressed: () =>
                                  _controller.setInvert(!state.invert),
                            ),
                            ActionChip(
                              avatar: _busyRoi
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.analytics_outlined),
                              label: const Text('Center ROI'),
                              onPressed: _busyRoi ? null : _analyzeCenterRoi,
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.ios_share_rounded),
                              label: const Text('Export PNG'),
                              onPressed: _exportPng,
                            ),
                          ],
                        ),
                        if (_roiStats != null) _RoiCard(stats: _roiStats!),
                        const SizedBox(height: 8),
                        _buildSlider(
                          'Level',
                          state.window.center,
                          -1000,
                          2000,
                          (final v) => _controller.setWindow(
                            state.window.copyWith(center: v),
                          ),
                        ),
                        _buildSlider(
                          'Width',
                          state.window.width,
                          1,
                          4000,
                          (final v) => _controller.setWindow(
                            state.window.copyWith(width: v),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _controller.reset,
                          icon: const Icon(Icons.restore_rounded),
                          label: const Text('Reset viewer'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 44),
                          ),
                        ),
                        const Divider(height: 32),
                        _MetadataGrid(
                          metadata: _controller.document!.metadata,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSlider(
    final String label,
    final double value,
    final double min,
    final double max,
    final ValueChanged<double> onChanged,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              value.toStringAsFixed(0),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RoiCard extends StatelessWidget {
  const _RoiCard({required this.stats});

  final RoiStatistics stats;

  @override
  Widget build(BuildContext context) {
    String fmt(final double v) => v.toStringAsFixed(1);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat(context, 'Pixels', '${stats.pixelCount}'),
            _stat(context, 'Min', fmt(stats.min)),
            _stat(context, 'Max', fmt(stats.max)),
            _stat(context, 'Mean', fmt(stats.mean)),
            _stat(context, 'StdDev', fmt(stats.stdDev)),
          ],
        ),
      ),
    );
  }

  Widget _stat(final BuildContext context, final String key, final String val) {
    return Column(
      children: [
        Text(
          key,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          val,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _MetadataGrid extends StatelessWidget {
  const _MetadataGrid({required this.metadata});

  final DicomMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final entries = <String, String>{
      'Resolution': '${metadata.columns} × ${metadata.rows}',
      'Modality': metadata.modality?.name ?? '—',
      'Patient': metadata.patientName ?? 'Anonymous',
      'Photometric': metadata.photometricInterpretation.name,
      'Samples/px': '${metadata.samplesPerPixel}',
      'Bits allocated': '${metadata.bitsAllocated}',
      'Bits stored': '${metadata.bitsStored}',
      'High bit': '${metadata.highBit}',
      'Pixel repr.': metadata.pixelRepresentation.name,
      'Frames': '${metadata.numberOfFrames}',
      'Window': metadata.windowPresets.isNotEmpty
          ? '${metadata.windowPresets.first.center.toStringAsFixed(0)} / '
                '${metadata.windowPresets.first.width.toStringAsFixed(0)}'
          : '—',
      'Spacing': metadata.pixelSpacing != null
          ? '${metadata.pixelSpacing!.row} \\ ${metadata.pixelSpacing!.column}'
          : '—',
    };
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.5,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: [
        for (final entry in entries.entries) _metaTile(context, entry),
      ],
    );
  }

  Widget _metaTile(
    final BuildContext context,
    final MapEntry<String, String> entry,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.key,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            entry.value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
