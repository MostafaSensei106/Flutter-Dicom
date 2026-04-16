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
      title: 'Advanced DICOM Viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
      ),
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'FLUTTER DICOM',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainer,
        elevation: 0,
        actions: [
          IconButton.filledTonal(
            onPressed: _pickAndLoadFile,
            icon: const Icon(Icons.file_open_rounded),
            tooltip: 'Open DICOM File',
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: () => _controller.clear(),
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Row(
            children: [
              // Main Viewer Area
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: colorScheme.outlineVariant,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        DicomViewer(controller: _controller),
                        if (!_controller.hasData && !_controller.isLoading)
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.medical_services_outlined,
                                  size: 64,
                                  color: colorScheme.primary.withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Ready to load DICOM',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                  onPressed: _pickAndLoadFile,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Select File'),
                                ),
                              ],
                            ),
                          ),
                        if (_controller.hasData) _buildOverlayInfo(colorScheme),
                      ],
                    ),
                  ),
                ),
              ),

              // Control Panel Sidebar
              if (_controller.hasData)
                _buildSidebar(colorScheme)
              else
                const SizedBox.shrink(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverlayInfo(ColorScheme colorScheme) {
    final meta = _controller.metadata!;
    return Positioned(
      bottom: 24,
      left: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              meta.patientName.isEmpty ? 'Anonymous' : meta.patientName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              '${meta.width} x ${meta.height} • ${meta.bitsStored} bit',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(ColorScheme colorScheme) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _SectionHeader(
            title: 'WINDOWING',
            icon: Icons.contrast_rounded,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 16),
          _buildSliderTile(
            label: 'Level (Center)',
            value: _controller.windowCenter ?? 0,
            min: -1000,
            max: 2000,
            onChanged: (val) => _controller.updateWindowing(center: val),
            colorScheme: colorScheme,
          ),
          _buildSliderTile(
            label: 'Width',
            value: _controller.windowWidth ?? 0,
            min: 1,
            max: 4000,
            onChanged: (val) => _controller.updateWindowing(width: val),
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _controller.resetWindowing,
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Reset Windowing'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 32),
          _SectionHeader(
            title: 'METADATA',
            icon: Icons.info_outline_rounded,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 16),
          _MetadataTile(
            label: 'Modality',
            value: 'CT/MR', // You could extract this from metadata if added
            colorScheme: colorScheme,
          ),
          _MetadataTile(
            label: 'Resolution',
            value: '${_controller.metadata?.width} x ${_controller.metadata?.height}',
            colorScheme: colorScheme,
          ),
          _MetadataTile(
            label: 'Samples',
            value: '${_controller.metadata?.samplesPerPixel}',
            colorScheme: colorScheme,
          ),
          _MetadataTile(
            label: 'Bits Stored',
            value: '${_controller.metadata?.bitsStored}',
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 32),
          _SectionHeader(
            title: 'INSTRUCTIONS',
            icon: Icons.touch_app_rounded,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 12),
          Text(
            '• Drag on image to adjust WC/WW\n'
            '• Pinch to zoom / Pan to move\n'
            '• Double tap to reset view',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderTile({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                value.toStringAsFixed(0),
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
              activeColor: colorScheme.primary,
              inactiveColor: colorScheme.primaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final ColorScheme colorScheme;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.secondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: colorScheme.secondary,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}

class _MetadataTile extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _MetadataTile({
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
