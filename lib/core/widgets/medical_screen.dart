import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dicom/core/controller/dicom_controller.dart';
import 'package:flutter_dicom/core/widgets/dicom_viewer.dart';

class MedicalScreen extends StatefulWidget {
  final String dicomPath;
  const MedicalScreen({super.key, required this.dicomPath});

  @override
  State<MedicalScreen> createState() => _MedicalScreenState();
}

class _MedicalScreenState extends State<MedicalScreen> {
  late final DicomController _dicomController;

  @override
  void initState() {
    super.initState();
    _dicomController = DicomController();

    _dicomController.loadFromFile(filePath: widget.dicomPath);
  }

  @override
  void dispose() {
    _dicomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DICOM Native Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _dicomController.resetWindowing,
          ),
        ],
      ),
      body: DicomViewer(controller: _dicomController),
    );
  }
}
