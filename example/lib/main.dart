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
    onFrame: (index) => _controller.setFrame(index),
  );

  @override
  void dispose() {
    _cine.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickAndLoadFile() async {
    final result = await FilePicker.pickFiles(type: FileType.any);

    if (result != null && result.files.single.path != null) {
      try {
        await _controller.load(
          DicomSource.file(result.files.single.path!),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading DICOM: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
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
            onPressed: _pickAndLoadFile,
            icon: const Icon(Icons.file_open_rounded),
          ),
          IconButton(
            onPressed: () => _controller.reset(),
            icon: const Icon(Icons.restore_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<DicomViewerState>(
        stream: _controller.states,
        initialData: _controller.state,
        builder: (context, snapshot) {
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
                                  onChanged: (v) =>
                                      _controller.setFrame(v.toInt()),
                                ),
                              ),
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
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildSlider(
                          'Level',
                          state.window.center,
                          -1000,
                          2000,
                          (v) => _controller.setWindow(
                            state.window.copyWith(center: v),
                          ),
                        ),
                        _buildSlider(
                          'Width',
                          state.window.width,
                          1,
                          4000,
                          (v) => _controller.setWindow(
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
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
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

  Widget _metaTile(BuildContext context, MapEntry<String, String> entry) {
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
