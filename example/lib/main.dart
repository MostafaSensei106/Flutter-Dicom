import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dicom/flutter_dicom.dart';

import 'measure_tab.dart';
import 'share_tab.dart';
import 'volume_tab.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _appEngine = await DicomEngine.create();

  runApp(const MyApp());
}

/// Engine instance owning the native bridge and parser wiring.
late DicomEngine _appEngine;

/// Shared workstation state: one controller drives every tab.
final class Workstation {
  Workstation({required this.engine}) {
    controller = DefaultDicomViewerController(parser: engine.parser);
    cine = DefaultDicomCineController(
      onFrame: (final index) => controller.setFrame(index),
    );
  }

  /// Engine facade (open / series / export).
  final DicomEngine engine;

  /// Viewer controller shared by the Viewer and Measure tabs.
  late final DefaultDicomViewerController controller;

  /// Cine playback driving [controller].
  late final DefaultDicomCineController cine;

  /// Custom window presets for this session.
  final DicomPresetStore presetStore = InMemoryDicomPresetStore();

  /// Annotations edited in the Measure tab.
  final DicomAnnotationController annotations =
      InMemoryDicomAnnotationController();

  /// File paths backing the current document (series order when known).
  List<String> documentPaths = const [];

  void dispose() {
    cine.dispose();
    controller.dispose();
    annotations.dispose();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.engineOverride});

  /// Engine override for tests (production uses the global from `main()`).
  final DicomEngine? engineOverride;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter DICOM Workstation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: DicomDemoScreen(engine: engineOverride ?? _appEngine),
    );
  }
}

class DicomDemoScreen extends StatefulWidget {
  const DicomDemoScreen({required this.engine, super.key});

  final DicomEngine engine;

  @override
  State<DicomDemoScreen> createState() => _DicomDemoScreenState();
}

class _DicomDemoScreenState extends State<DicomDemoScreen> {
  late final Workstation _workstation = Workstation(engine: widget.engine);
  int _tab = 0;
  double _fps = 24;

  @override
  void dispose() {
    _workstation.dispose();
    super.dispose();
  }

  void _showError(final Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  /// Opens a single file through the file-system path source.
  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || files.single.path == null) return;
    try {
      final path = files.single.path!;
      await _workstation.controller.load(DicomSource.file(path));
      setState(() => _workstation.documentPaths = [path]);
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
      await _workstation.controller.load(DicomSource.bytes(bytes));
      setState(() => _workstation.documentPaths = const []);
    } catch (e) {
      _showError(e);
    }
  }

  /// Opens a folder of slices as one scrub-able series document.
  ///
  /// Slices are spatially sorted (Image Position/Orientation) through the
  /// engine series loader — never raw filesystem order.
  Future<void> _pickSeriesFolder() async {
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null) return;
    try {
      final paths = Directory(dirPath)
          .listSync()
          .whereType<File>()
          .map((final f) => f.path)
          .where((final p) => p.toLowerCase().endsWith('.dcm'))
          .toList();
      if (paths.isEmpty) {
        throw const DicomProcessingException('No .dcm files found');
      }
      final series = await _workstation.engine.openSeries(
        DicomSource.files(paths),
      );
      await _workstation.controller.load(DicomSource.files(series.filePaths));
      setState(() => _workstation.documentPaths = series.filePaths);
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DICOM'),
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
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          ViewerTab(
            workstation: _workstation,
            fps: _fps,
            onFpsChanged: (final v) {
              setState(() => _fps = v);
              _workstation.cine.setFps(v);
            },
            onLoaded: () => setState(() {}),
          ),
          MeasureTab(workstation: _workstation, onError: _showError),
          VolumeTab(workstation: _workstation, onError: _showError),
          ShareTab(workstation: _workstation, onError: _showError),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (final i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.visibility_rounded),
            label: 'Viewer',
          ),
          NavigationDestination(
            icon: Icon(Icons.straighten_rounded),
            label: 'Measure',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_in_ar_rounded),
            label: 'Volume',
          ),
          NavigationDestination(
            icon: Icon(Icons.ios_share_rounded),
            label: 'Share',
          ),
        ],
      ),
    );
  }
}

/// Frame scrubber shared by viewer flows (M1 navigation + M3 cine).
class FrameControls extends StatelessWidget {
  const FrameControls({
    required this.controller,
    required this.cine,
    super.key,
  });

  final DefaultDicomViewerController controller;
  final DefaultDicomCineController cine;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DicomViewerState>(
      stream: controller.states,
      initialData: controller.state,
      builder: (final context, final snapshot) {
        final state = snapshot.data ?? controller.state;
        if (state.frameCount <= 1) return const SizedBox.shrink();
        return Row(
          children: [
            IconButton(
              tooltip: 'Previous frame',
              onPressed: () => controller.previousFrame(),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              tooltip: cine.playing ? 'Pause cine' : 'Play cine',
              onPressed: () {
                if (cine.playing) {
                  cine.pause();
                } else {
                  cine.play(frameCount: state.frameCount);
                }
              },
              icon: Icon(
                cine.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            ),
            IconButton(
              tooltip: 'Stop cine',
              onPressed: () => cine.stop(),
              icon: const Icon(Icons.stop_rounded),
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
                label: '${state.currentFrame + 1} / ${state.frameCount}',
                onChanged: (final v) => controller.setFrame(v.toInt()),
              ),
            ),
            Text('${state.currentFrame + 1} / ${state.frameCount}'),
            IconButton(
              tooltip: 'Next frame',
              onPressed: () => controller.nextFrame(),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        );
      },
    );
  }
}

/// Viewer tab: windowing, presets, transform, frames, cine, metadata.
class ViewerTab extends StatefulWidget {
  const ViewerTab({
    required this.workstation,
    required this.fps,
    required this.onFpsChanged,
    required this.onLoaded,
    super.key,
  });

  final Workstation workstation;
  final double fps;
  final ValueChanged<double> onFpsChanged;
  final VoidCallback onLoaded;

  @override
  State<ViewerTab> createState() => _ViewerTabState();
}

class _ViewerTabState extends State<ViewerTab> {
  final _presetName = TextEditingController();
  List<DicomWindow> _customPresets = const [];

  @override
  void dispose() {
    _presetName.dispose();
    super.dispose();
  }

  Future<void> _reloadCustom() async {
    final presets = await widget.workstation.presetStore.load();
    if (mounted) setState(() => _customPresets = presets);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.workstation.controller;
    final cine = widget.workstation.cine;
    return StreamBuilder<DicomViewerState>(
      stream: controller.states,
      initialData: controller.state,
      builder: (final context, final snapshot) {
        final state = snapshot.data ?? controller.state;
        final ready = state.status is DicomViewerReady;
        return LayoutBuilder(
          builder: (final context, final constraints) {
            final side = math.min(
              constraints.maxWidth,
              (constraints.maxHeight * 0.62).clamp(200.0, 560.0),
            );
            return Column(
              children: [
                SizedBox(
                  width: side,
                  height: side,
                  child: Stack(
                    children: [
                      DicomViewer(
                        controller: controller,
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
                                controller.document?.metadata.patientName ??
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
                          _ViewerControls(
                            controller: controller,
                            cine: cine,
                            fps: widget.fps,
                            onFpsChanged: widget.onFpsChanged,
                            onSavePreset: (final name, final window) async {
                              await widget.workstation.presetStore.save(
                                name,
                                window,
                              );
                              await _reloadCustom();
                            },
                            presetName: _presetName,
                            customPresets: _customPresets,
                          ),
                          const Divider(height: 32),
                          _MetadataGrid(
                            metadata: controller.document!.metadata,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Scrollable viewer controls below the image (presets, transform, levels).
class _ViewerControls extends StatelessWidget {
  const _ViewerControls({
    required this.controller,
    required this.cine,
    required this.fps,
    required this.onFpsChanged,
    required this.onSavePreset,
    required this.presetName,
    required this.customPresets,
  });

  final DefaultDicomViewerController controller;
  final DefaultDicomCineController cine;
  final double fps;
  final ValueChanged<double> onFpsChanged;
  final Future<void> Function(String name, DicomWindow window) onSavePreset;
  final TextEditingController presetName;
  final List<DicomWindow> customPresets;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    return Column(
      children: [
        FrameControls(controller: controller, cine: cine),
        Row(
          children: [
            const Text('FPS'),
            Expanded(
              child: Slider(
                value: fps,
                min: 1,
                max: 60,
                divisions: 59,
                label: fps.toStringAsFixed(0),
                onChanged: onFpsChanged,
              ),
            ),
            Text(fps.toStringAsFixed(0)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in DicomWindowPreset.all)
              ActionChip(
                label: Text(preset.label ?? ''),
                onPressed: () => controller.setWindow(preset),
              ),
            for (final preset in customPresets)
              ActionChip(
                avatar: const Icon(Icons.star_rounded, size: 16),
                label: Text(preset.label ?? ''),
                onPressed: () => controller.setWindow(preset),
              ),
            ActionChip(
              label: Text(state.invert ? 'Uninvert' : 'Invert'),
              onPressed: () => controller.setInvert(!state.invert),
            ),
            ActionChip(
              label: const Text('Flip H'),
              onPressed: () => controller.setFlipH(!state.flipH),
            ),
            ActionChip(
              label: const Text('Flip V'),
              onPressed: () => controller.setFlipV(!state.flipV),
            ),
            ActionChip(
              label: const Text('⟲ 15°'),
              onPressed: () => controller.rotate(-15),
            ),
            ActionChip(
              label: const Text('15° ⟳'),
              onPressed: () => controller.rotate(15),
            ),
            ActionChip(
              label: const Text('Zoom +'),
              onPressed: () => controller.zoom(state.zoom * 1.25),
            ),
            ActionChip(
              label: const Text('Zoom −'),
              onPressed: () => controller.zoom(state.zoom / 1.25),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: presetName,
                decoration: const InputDecoration(
                  labelText: 'Custom preset name',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () async {
                final name = presetName.text.trim();
                if (name.isEmpty) return;
                presetName.clear();
                await onSavePreset(name, controller.state.window);
              },
              child: const Text('Save window'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _levelSlider(
          context,
          'Level',
          state.window.center,
          -1000,
          2000,
          (final v) => controller.setWindow(state.window.copyWith(center: v)),
        ),
        _levelSlider(
          context,
          'Width',
          state.window.width,
          1,
          4000,
          (final v) => controller.setWindow(state.window.copyWith(width: v)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: controller.reset,
          icon: const Icon(Icons.restore_rounded),
          label: const Text('Reset viewer'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
          ),
        ),
      ],
    );
  }

  Widget _levelSlider(
    final BuildContext context,
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
