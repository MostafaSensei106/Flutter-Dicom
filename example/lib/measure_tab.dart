import 'package:flutter/material.dart';
import 'package:flutter_dicom/flutter_dicom.dart';

import 'main.dart';

/// Measure tab: probe readout, ruler, ROI, annotations, segmentation.
///
/// A second [DicomViewer] shares the workstation controller — dumb widgets
/// over one reactive state — wrapped in a tap layer that maps touches back
/// through the same view transform for analysis.
class MeasureTab extends StatefulWidget {
  const MeasureTab({
    required this.workstation,
    required this.onError,
    super.key,
  });

  final Workstation workstation;
  final ValueChanged<Object> onError;

  @override
  State<MeasureTab> createState() => _MeasureTabState();
}

class _MeasureTabState extends State<MeasureTab> {
  DicomProbeResult? _probe;
  DicomPoint? _rulerA;
  DicomPoint? _rulerB;
  bool _ellipseRoi = false;
  RoiStatistics? _roiStats;
  bool _busyRoi = false;
  DicomSegmentationMask? _mask;
  DicomSegmentationStats? _segStats;
  bool _busySeg = false;
  double _segLower = 200;
  double _segUpper = 800;

  DicomViewerController get _controller => widget.workstation.controller;

  void _onTap(final Offset local, final Size fitted) {
    final pixels = _controller.pixels;
    if (pixels == null) return;
    final viewport =
        DicomViewport(width: fitted.width, height: fitted.height);
    setState(() {
      _probe = _controller.probeAt(
        DicomPoint(local.dx, local.dy),
        viewport,
      );
      final imagePoint = _controller.state.viewTransform.screenToImage(
        DicomPoint(local.dx, local.dy),
        viewport,
        pixels.width,
        pixels.height,
      );
      if (imagePoint != null) {
        if (_rulerA == null) {
          _rulerA = imagePoint;
          _rulerB = null;
        } else {
          _rulerB = imagePoint;
        }
      }
    });
  }

  Size _fitContain(
      final double maxWidth, final double maxHeight, final double aspect) {
    if (!maxWidth.isFinite || !maxHeight.isFinite || aspect <= 0) {
      return const Size(300, 300);
    }
    var width = maxWidth;
    var height = width / aspect;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspect;
    }
    return Size(width, height);
  }

  Future<void> _analyzeRoi() async {
    final pixels = _controller.pixels;
    if (pixels == null) return;
    setState(() => _busyRoi = true);
    try {
      final bounds = DicomRect(
        pixels.width / 4,
        pixels.height / 4,
        pixels.width / 2,
        pixels.height / 2,
      );
      final stats = _ellipseRoi
          ? await DicomEllipseRoi(bounds).analyze(pixels)
          : await DicomRoi(bounds).analyze(pixels);
      if (mounted) setState(() => _roiStats = stats);
    } catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => _busyRoi = false);
    }
  }

  Future<void> _segment() async {
    final pixels = _controller.pixels;
    if (pixels == null) return;
    setState(() => _busySeg = true);
    try {
      final mask = await ThresholdSegmentation(
        lower: _segLower,
        upper: _segUpper,
      ).segment(pixels);
      if (mounted) {
        setState(() {
          _mask = mask;
          _segStats = DicomSegmentationStats.compute(
            mask,
            spacing: _controller.geometry?.pixelSpacing,
          );
        });
      }
    } catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => _busySeg = false);
    }
  }

  void _addAnnotation(final DicomAnnotation annotation) {
    widget.workstation.annotations.add(annotation);
    setState(() {});
  }

  String _newId(final String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  @override
  Widget build(BuildContext context) {
    final pixels = _controller.pixels;
    final geometry = _controller.geometry;
    if (pixels == null || geometry == null) {
      return const Center(child: Text('Load an image in the Viewer tab.'));
    }
    final aspect = pixels.width / pixels.height;
    final overlays = <DicomOverlay>[
      const ScaleBarOverlay(),
      AnnotationOverlay(
        annotations: widget.workstation.annotations.annotations,
      ),
      if (_rulerA != null && _rulerB != null)
        RulerOverlay(start: _rulerA!, end: _rulerB!),
      if (_roiStats != null)
        _ellipseRoi
            ? RoiOverlay.ellipse(_centerBounds(pixels))
            : RoiOverlay.rectangle(_centerBounds(pixels)),
      if (_mask != null) MaskOverlay(mask: _mask!),
      const PixelProbeOverlay(),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (final context, final constraints) {
              final fitted = _fitContain(
                constraints.maxWidth,
                320,
                aspect,
              );
              return Center(
                child: SizedBox(
                  width: fitted.width,
                  height: fitted.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (final details) =>
                        _onTap(details.localPosition, fitted),
                    child: DicomViewer(
                      controller: _controller,
                      overlays: overlays,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          if (_probe != null) _ProbeCard(result: _probe!),
          const SizedBox(height: 8),
          _SectionCard(
            title: 'Ruler (tap twice)',
            trailing: TextButton(
              onPressed: () => setState(() {
                _rulerA = null;
                _rulerB = null;
              }),
              child: const Text('Clear'),
            ),
            child: _rulerA != null && _rulerB != null
                ? _RulerLabel(start: _rulerA!, end: _rulerB!, geometry: geometry)
                : const Text('Tap two points on the image.'),
          ),
          const SizedBox(height: 8),
          _SectionCard(
            title: 'ROI statistics',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChoiceChip(
                  label: const Text('Rect'),
                  selected: !_ellipseRoi,
                  onSelected: (final _) =>
                      setState(() => _ellipseRoi = false),
                ),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: const Text('Ellipse'),
                  selected: _ellipseRoi,
                  onSelected: (final _) =>
                      setState(() => _ellipseRoi = true),
                ),
              ],
            ),
            child: Column(
              children: [
                FilledButton.tonal(
                  onPressed: _busyRoi ? null : _analyzeRoi,
                  child: Text(
                    _busyRoi ? 'Analyzing…' : 'Analyze center ROI',
                  ),
                ),
                if (_roiStats != null) ...[
                  const SizedBox(height: 8),
                  _StatsRow(entries: {
                    'Pixels': '${_roiStats!.pixelCount}',
                    'Min': _roiStats!.min.toStringAsFixed(1),
                    'Max': _roiStats!.max.toStringAsFixed(1),
                    'Mean': _roiStats!.mean.toStringAsFixed(1),
                    'Median': _roiStats!.median.toStringAsFixed(1),
                    'StdDev': _roiStats!.stdDev.toStringAsFixed(1),
                  }),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          _SectionCard(
            title: 'Annotations',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Undo',
                  onPressed: () {
                    widget.workstation.annotations.undo();
                    setState(() {});
                  },
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: 'Redo',
                  onPressed: () {
                    widget.workstation.annotations.redo();
                    setState(() {});
                  },
                  icon: const Icon(Icons.redo_rounded),
                ),
              ],
            ),
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Line'),
                      onPressed: () => _addAnnotation(
                        LineAnnotation(
                          id: _newId('line'),
                          start: DicomPoint(
                            pixels.width * 0.25,
                            pixels.height * 0.5,
                          ),
                          end: DicomPoint(
                            pixels.width * 0.75,
                            pixels.height * 0.5,
                          ),
                        ),
                      ),
                    ),
                    ActionChip(
                      label: const Text('Rect'),
                      onPressed: () => _addAnnotation(
                        RectangleAnnotation(
                          id: _newId('rect'),
                          rect: DicomRect(
                            pixels.width * 0.3,
                            pixels.height * 0.3,
                            pixels.width * 0.4,
                            pixels.height * 0.4,
                          ),
                        ),
                      ),
                    ),
                    ActionChip(
                      label: const Text('Arrow'),
                      onPressed: () => _addAnnotation(
                        ArrowAnnotation(
                          id: _newId('arrow'),
                          start: DicomPoint(
                            pixels.width * 0.2,
                            pixels.height * 0.2,
                          ),
                          end: DicomPoint(
                            pixels.width * 0.6,
                            pixels.height * 0.6,
                          ),
                        ),
                      ),
                    ),
                    ActionChip(
                      label: const Text('Text'),
                      onPressed: () => _addAnnotation(
                        TextAnnotation(
                          id: _newId('text'),
                          position: DicomPoint(
                            pixels.width * 0.5,
                            pixels.height * 0.2,
                          ),
                          text: 'Note',
                        ),
                      ),
                    ),
                  ],
                ),
                for (final annotation
                    in widget.workstation.annotations.annotations)
                  ListTile(
                    dense: true,
                    title: Text(
                      '${annotation.runtimeType} · ${annotation.id}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () {
                        widget.workstation.annotations
                            .remove(annotation.id);
                        setState(() {});
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _SectionCard(
            title: 'Segmentation (threshold)',
            child: Column(
              children: [
                _rangeSlider(
                  'Lower',
                  _segLower,
                  -1000,
                  2000,
                  (final v) => setState(() => _segLower = v),
                ),
                _rangeSlider(
                  'Upper',
                  _segUpper,
                  -1000,
                  2000,
                  (final v) => setState(() => _segUpper = v),
                ),
                FilledButton.tonal(
                  onPressed: _busySeg ? null : _segment,
                  child:
                      Text(_busySeg ? 'Segmenting…' : 'Segment + overlay'),
                ),
                if (_segStats != null) ...[
                  const SizedBox(height: 8),
                  _StatsRow(entries: {
                    'Voxels': '${_segStats!.voxelCount}',
                    'Area': _segStats!.areaMm2 != null
                        ? '${_segStats!.areaMm2!.toStringAsFixed(1)} mm²'
                        : '—',
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  DicomRect _centerBounds(final DicomPixelData pixels) => DicomRect(
        pixels.width / 4,
        pixels.height / 4,
        pixels.width / 2,
        pixels.height / 2,
      );

  Widget _rangeSlider(
    final String label,
    final double value,
    final double min,
    final double max,
    final ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 52, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(value.toStringAsFixed(0)),
        ),
      ],
    );
  }
}

class _ProbeCard extends StatelessWidget {
  const _ProbeCard({required this.result});

  final DicomProbeResult result;

  @override
  Widget build(BuildContext context) {
    String mm(final List<double>? p) => p == null
        ? '—'
        : '(${p[0].toStringAsFixed(1)}, ${p[1].toStringAsFixed(1)}, '
            '${p[2].toStringAsFixed(1)})';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text('px (${result.coordinate.x.toInt()}, '
                '${result.coordinate.y.toInt()})'),
            Text('raw ${result.rawValue.toStringAsFixed(0)}'),
            Text('HU ${result.hu?.toStringAsFixed(0) ?? '—'}'),
            Text('mm ${mm(result.patientPosition)}'),
          ],
        ),
      ),
    );
  }
}

class _RulerLabel extends StatelessWidget {
  const _RulerLabel({
    required this.start,
    required this.end,
    required this.geometry,
  });

  final DicomPoint start;
  final DicomPoint end;
  final DicomGeometry geometry;

  @override
  Widget build(BuildContext context) {
    final m = const DicomRuler().measure(start, end, geometry);
    return Text(
      m.millimeters != null
          ? '${m.millimeters!.toStringAsFixed(1)} mm '
              '(${m.pixelDistance.toStringAsFixed(1)} px)'
          : '${m.pixelDistance.toStringAsFixed(1)} px (no spacing)',
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (trailing case final Widget trailing) trailing,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.entries});

  final Map<String, String> entries;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final e in entries.entries)
          Text('${e.key}: ${e.value}',
              style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
