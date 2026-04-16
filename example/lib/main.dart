import 'package:flutter/material.dart';
import 'package:flutter_dicom/flutter_dicom.dart';
import 'package:file_picker/file_picker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize the native library
  await RustLib.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter DICOM Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
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
  final DicomController _controller = DicomController();

  @override
  void initState() {
    super.initState();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickAndLoadFile() async {
    final result = await FilePicker.pickFiles(type: FileType.any);

    if (result != null && result.files.single.path != null) {
      try {
        await _controller.loadFromFile(filePath: result.files.single.path!);
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
            onPressed: () => _controller.clear(),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Column(
          children: [
            // Viewer
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  DicomViewer(controller: _controller),
                  if (_controller.hasData)
                    Positioned(
                      bottom: 12,
                      left: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _controller.metadata?.patientName ?? 'Anonymous',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_controller.metadata?.width} x ${_controller.metadata?.height}',
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

            // Controls — only when data loaded
            if (_controller.hasData)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Windowing sliders
                      _buildSlider(
                        'Level',
                        _controller.windowCenter ?? 0,
                        -1000,
                        2000,
                        (v) => _controller.updateWindowing(center: v),
                      ),
                      _buildSlider(
                        'Width',
                        _controller.windowWidth ?? 0,
                        1,
                        4000,
                        (v) => _controller.updateWindowing(width: v),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _controller.resetWindowing,
                        icon: const Icon(Icons.restore_rounded),
                        label: const Text('Reset windowing'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                        ),
                      ),
                      const Divider(height: 32),

                      // Metadata grid
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 2.5,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        children: [
                          _metaTile(
                            'Resolution',
                            '${_controller.metadata!.width} × ${_controller.metadata!.height}',
                          ),
                          _metaTile(
                            'Window center',
                            '${_controller.metadata!.windowCenter}',
                          ),
                          _metaTile(
                            'Window width',
                            '${_controller.metadata!.windowWidth}',
                          ),
                          _metaTile(
                            'Rescale intercept',
                            '${_controller.metadata!.rescaleIntercept}',
                          ),
                          _metaTile(
                            'Rescale slope',
                            '${_controller.metadata!.rescaleSlope}',
                          ),
                          _metaTile(
                            'Patient',
                            _controller.metadata!.patientName.isEmpty
                                ? 'Anonymous'
                                : _controller.metadata!.patientName,
                          ),
                          _metaTile(
                            'Photometric',
                            _controller.metadata!.photometricInterpretation,
                          ),
                          _metaTile(
                            'Samples/px',
                            '${_controller.metadata!.samplesPerPixel}',
                          ),
                          _metaTile(
                            'Bits allocated',
                            '${_controller.metadata!.bitsAllocated}',
                          ),
                          _metaTile(
                            'Bits stored',
                            '${_controller.metadata!.bitsStored}',
                          ),
                          _metaTile(
                            'High bit',
                            '${_controller.metadata!.highBit}',
                          ),
                          _metaTile(
                            'Px representation',
                            '${_controller.metadata!.pixelRepresentation}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
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

  Widget _metaTile(String key, String val) {
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
      ),
    );
  }
}
