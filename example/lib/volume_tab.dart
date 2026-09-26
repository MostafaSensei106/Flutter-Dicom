import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dicom/flutter_dicom.dart';

import 'main.dart';

/// Volume tab: assembly, MPR, MIP/MinIP, CPU 3D, PET/CT fusion.
///
/// Heavy CPU work runs on demand with progress; every result renders to an
/// in-memory PNG preview through the shared exporters.
class VolumeTab extends StatefulWidget {
  const VolumeTab({
    required this.workstation,
    required this.onError,
    super.key,
  });

  final Workstation workstation;
  final ValueChanged<Object> onError;

  @override
  State<VolumeTab> createState() => _VolumeTabState();
}

class _VolumeTabState extends State<VolumeTab> {
  DicomVoxelVolume? _volume;
  double? _progress;
  String _status = 'Load a series in the Viewer tab, then assemble.';

  DicomPlane _plane = DicomPlane.axial;
  double _mprPosition = 0;
  bool _trilinear = false;
  Uint8List? _mprPng;

  DicomProjectionType _projType = DicomProjectionType.maximum;
  DicomProjectionAxis _projAxis = DicomProjectionAxis.z;
  Uint8List? _projPng;

  Uint8List? _render3dPng;
  bool _busy3d = false;

  DicomPixelData? _pet;
  double _fusionAlpha = 0.5;
  double _fusionThreshold = 0.05;
  Uint8List? _fusionPng;

  Workstation get _w => widget.workstation;

  int _planeDepth(final DicomVoxelVolume v) => switch (_plane) {
        DicomPlane.axial => v.depth,
        DicomPlane.coronal => v.height,
        DicomPlane.sagittal => v.width,
        DicomPlane.oblique => v.depth,
      };

  Future<void> _assemble() async {
    final paths = _w.documentPaths;
    if (paths.isEmpty) {
      setState(() => _status = 'Assemble needs files (open a file or series).');
      return;
    }
    setState(() {
      _progress = 0;
      _status = 'Reading metadata…';
      _volume = null;
    });
    try {
      final series =
          await _w.engine.openSeries(DicomSource.files(paths));
      final slices = <DicomPixelData>[];
      for (var i = 0; i < series.filePaths.length; i++) {
        final doc =
            await _w.engine.open(DicomSource.file(series.filePaths[i]));
        slices.add((await doc.frames.get(0)).pixelData!);
        if (mounted && (i % 10 == 0 || i == series.filePaths.length - 1)) {
          setState(() {
            _progress = (i + 1) / series.filePaths.length;
            _status = 'Decoding slice ${i + 1} / ${series.filePaths.length}…';
          });
        }
      }
      final first = slices.first;
      final meta = DicomVolume.fromSeries(
        series,
        width: first.width,
        height: first.height,
      );
      final volume = DicomVoxelVolume.assemble(meta: meta, slices: slices);
      if (mounted) {
        setState(() {
          _volume = volume;
          _progress = null;
          _mprPosition = 0;
          _status = 'Volume ready: ${volume.width}×${volume.height}'
              '×${volume.depth} (${volume.meta.voxelSpacing.map((final s) => s.toStringAsFixed(2)).join('×')} mm)';
        });
      }
    } catch (e) {
      widget.onError(e);
      if (mounted) {
        setState(() {
          _progress = null;
          _status = 'Assembly failed.';
        });
      }
    }
  }

  Future<Uint8List> _toPng(final DicomPixelData pixels) =>
      const PngDicomExporter().exportWindowed(
        pixels,
        _w.controller.state.window,
      );

  Future<void> _renderMpr() async {
    final volume = _volume;
    if (volume == null) return;
    try {
      final strategy = _trilinear
          ? const TrilinearReconstruction()
          : const NearestReconstruction();
      final slice = await strategy.reconstruct(volume, _plane, _mprPosition);
      final png = await _toPng(slice);
      if (mounted) setState(() => _mprPng = png);
    } catch (e) {
      widget.onError(e);
    }
  }

  Future<void> _renderProjection() async {
    final volume = _volume;
    if (volume == null) return;
    try {
      final strategy = _projType == DicomProjectionType.maximum
          ? const MipProjection()
          : const MinIpProjection();
      final out = await strategy.project(
        volume,
        DicomProjectionOptions(type: _projType, axis: _projAxis),
      );
      final png = await _toPng(out);
      if (mounted) setState(() => _projPng = png);
    } catch (e) {
      widget.onError(e);
    }
  }

  Future<void> _render3d() async {
    final volume = _volume;
    if (volume == null || _busy3d) return;
    setState(() => _busy3d = true);
    try {
      final frame = await const CpuCompositeVolumeRenderer().render(
        volume,
        DicomVolumeRenderOptions(
          outputWidth: 128,
          outputHeight: 128,
          transferFunction: DicomTransferFunction(
            window: _w.controller.state.window,
          ),
        ),
      );
      final png = await _toPng(frame);
      if (mounted) setState(() => _render3dPng = png);
    } catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => _busy3d = false);
    }
  }

  Future<void> _pickPet() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return;
    try {
      final bytes = await files.single.xFile.readAsBytes();
      final doc = await _w.engine.open(DicomSource.bytes(bytes));
      final pixels = (await doc.frames.get(0)).pixelData!;
      if (mounted) setState(() => _pet = pixels);
    } catch (e) {
      widget.onError(e);
    }
  }

  Future<void> _renderFusion() async {
    final ct = _w.controller.pixels;
    final pet = _pet;
    if (ct == null || pet == null) return;
    try {
      // Wide auto window over sampled PET values.
      var min = double.infinity;
      var max = double.negativeInfinity;
      final n = pet.length < 2000 ? pet.length : 2000;
      for (var i = 0; i < n; i++) {
        final v = pet.modalityAt(i * pet.length ~/ n);
        if (v < min) min = v;
        if (v > max) max = v;
      }
      final fused = await DicomFusionRenderer(
        alpha: _fusionAlpha,
        threshold: _fusionThreshold,
      ).render(
        ct: ct,
        ctWindow: _w.controller.state.window,
        pet: pet,
        petWindow: DicomWindow(
          center: (min + max) / 2,
          width: (max - min).clamp(1.0, double.infinity),
        ),
      );
      final png = await _toPng(fused);
      if (mounted) setState(() => _fusionPng = png);
    } catch (e) {
      widget.onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final volume = _volume;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _progress != null ? null : _assemble,
            icon: const Icon(Icons.view_in_ar_rounded),
            label: const Text('Assemble volume from series'),
          ),
          const SizedBox(height: 8),
          if (_progress != null)
            LinearProgressIndicator(value: _progress),
          Text(_status),
          const Divider(height: 32),
          _PreviewCard(title: 'MPR', png: _mprPng, child: _mprControls(volume)),
          const SizedBox(height: 8),
          _PreviewCard(
            title: 'MIP / MinIP',
            png: _projPng,
            child: _projectionControls(volume),
          ),
          const SizedBox(height: 8),
          _PreviewCard(
            title: '3D volume rendering (CPU)',
            png: _render3dPng,
            child: FilledButton.tonal(
              onPressed:
                  volume == null || _busy3d ? null : _render3d,
              child: Text(_busy3d ? 'Rendering…' : 'Render 3D'),
            ),
          ),
          const SizedBox(height: 8),
          _PreviewCard(
            title: 'PET/CT fusion',
            png: _fusionPng,
            child: _fusionControls(),
          ),
        ],
      ),
    );
  }

  Widget _mprControls(final DicomVoxelVolume? volume) {
    final depth = volume == null ? 1 : _planeDepth(volume);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButton<DicomPlane>(
                value: _plane,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: DicomPlane.axial,
                    child: Text('Axial'),
                  ),
                  DropdownMenuItem(
                    value: DicomPlane.coronal,
                    child: Text('Coronal'),
                  ),
                  DropdownMenuItem(
                    value: DicomPlane.sagittal,
                    child: Text('Sagittal'),
                  ),
                ],
                onChanged: (final v) => setState(() {
                  _plane = v ?? DicomPlane.axial;
                  _mprPosition = 0;
                }),
              ),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Trilinear'),
              selected: _trilinear,
              onSelected: (final v) =>
                  setState(() => _trilinear = v),
            ),
          ],
        ),
        Row(
          children: [
            const Text('Slice'),
            Expanded(
              child: Slider(
                value: _mprPosition.clamp(0, (depth - 1).toDouble()),
                min: 0,
                max: (depth - 1).toDouble(),
                divisions: depth <= 1 ? 1 : depth - 1,
                label: _mprPosition.round().toString(),
                onChanged: (final v) =>
                    setState(() => _mprPosition = v),
              ),
            ),
            Text(_mprPosition.round().toString()),
          ],
        ),
        FilledButton.tonal(
          onPressed: volume == null ? null : _renderMpr,
          child: const Text('Render MPR slice'),
        ),
      ],
    );
  }

  Widget _projectionControls(final DicomVoxelVolume? volume) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButton<DicomProjectionType>(
                value: _projType,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: DicomProjectionType.maximum,
                    child: Text('MIP'),
                  ),
                  DropdownMenuItem(
                    value: DicomProjectionType.minimum,
                    child: Text('MinIP'),
                  ),
                ],
                onChanged: (final v) => setState(
                  () => _projType = v ?? DicomProjectionType.maximum,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<DicomProjectionAxis>(
                value: _projAxis,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: DicomProjectionAxis.x,
                    child: Text('Axis X'),
                  ),
                  DropdownMenuItem(
                    value: DicomProjectionAxis.y,
                    child: Text('Axis Y'),
                  ),
                  DropdownMenuItem(
                    value: DicomProjectionAxis.z,
                    child: Text('Axis Z'),
                  ),
                ],
                onChanged: (final v) => setState(
                  () => _projAxis = v ?? DicomProjectionAxis.z,
                ),
              ),
            ),
          ],
        ),
        FilledButton.tonal(
          onPressed: volume == null ? null : _renderProjection,
          child: const Text('Render projection'),
        ),
      ],
    );
  }

  Widget _fusionControls() {
    final ctReady = _w.controller.pixels != null;
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: _pickPet,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(_pet == null ? 'Pick overlay (PET)' : 'Overlay loaded ✓'),
        ),
        Row(
          children: [
            const Text('Alpha'),
            Expanded(
              child: Slider(
                value: _fusionAlpha,
                min: 0,
                max: 1,
                onChanged: (final v) =>
                    setState(() => _fusionAlpha = v),
              ),
            ),
            Text(_fusionAlpha.toStringAsFixed(2)),
          ],
        ),
        Row(
          children: [
            const Text('Cutoff'),
            Expanded(
              child: Slider(
                value: _fusionThreshold,
                min: 0,
                max: 0.5,
                onChanged: (final v) =>
                    setState(() => _fusionThreshold = v),
              ),
            ),
            Text(_fusionThreshold.toStringAsFixed(2)),
          ],
        ),
        FilledButton.tonal(
          onPressed: !ctReady || _pet == null ? null : _renderFusion,
          child: const Text('Render fusion'),
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.title,
    required this.child,
    this.png,
  });

  final String title;
  final Widget child;
  final Uint8List? png;

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
            if (png != null) ...[
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  color: Colors.black,
                  child: Image.memory(png!, fit: BoxFit.contain),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
