import 'package:flutter/material.dart';
import 'package:flutter_dicom/flutter_dicom.dart';
import 'package:file_picker/file_picker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter DICOM Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
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
    final result = await FilePicker.pickFiles(
      type: FileType.any, // DICOM files often don't have extension or have .dcm
    );

    if (result != null && result.files.single.path != null) {
      try {
        await _controller.loadFromFile(filePath: result.files.single.path!);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DICOM Medical Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: _pickAndLoadFile,
            tooltip: 'Open DICOM File',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _controller.resetWindowing,
            tooltip: 'Reset Contrast',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: DicomViewer(controller: _controller)),
          if (_controller.hasData) _buildMetadataPanel(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndLoadFile,
        child: const Icon(Icons.file_open),
      ),
    );
  }

  Widget _buildMetadataPanel() {
    final meta = _controller.metadata!;
    return Container(
      padding: const EdgeInsets.all(16.0),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Patient: ${meta.patientName}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Resolution: ${meta.width}x${meta.height}'),
              Text(
                'HU: ${_controller.windowCenter?.toStringAsFixed(0)} / ${_controller.windowWidth?.toStringAsFixed(0)}',
              ),
            ],
          ),
          const Text(
            'Drag to adjust contrast (L/R) and brightness (U/D)',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
