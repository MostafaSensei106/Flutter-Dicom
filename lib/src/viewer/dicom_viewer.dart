import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../application/viewer/viewer_state.dart';
import '../domain/dicom_geometry.dart';
import '../presentation/overlays/dicom_overlay.dart';
import 'dicom_viewer_controller.dart';
import 'painting.dart';

/// A dumb, composable DICOM viewer.
///
/// All state lives in [DicomViewerController]; this widget renders the
/// current snapshot and forwards gestures. Decorations compose via
/// [overlays] — no viewer properties are added per feature.
///
/// ```dart
/// DicomViewer(
///   controller: controller,
///   overlays: [ScaleBarOverlay(), OrientationOverlay(), PixelProbeOverlay()],
/// )
/// ```
class DicomViewer extends StatefulWidget {
  const DicomViewer({
    required this.controller,
    super.key,
    this.loadingBuilder,
    this.errorBuilder,
    this.emptyBuilder,
    this.overlays = const [],
    this.windowDrag = true,
    this.probeInteraction = true,
  });

  final DicomViewerController controller;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  final Widget Function(BuildContext context)? emptyBuilder;

  /// Paint-based decorations drawn over the image.
  final List<DicomOverlay> overlays;

  /// Whether horizontal/vertical drags adjust window width/center.
  final bool windowDrag;

  /// Whether taps / hovers set the probe point for [overlays].
  final bool probeInteraction;

  @override
  State<DicomViewer> createState() => _DicomViewerState();
}

class _DicomViewerState extends State<DicomViewer> {
  ui.FragmentShader? _shader;
  String? _shaderError;
  DicomPoint? _probeImagePoint;

  @override
  void initState() {
    super.initState();
    loadDicomShader().then(
      (final shader) {
        if (mounted) setState(() => _shader = shader);
      },
      onError: (final Object e) {
        if (mounted) setState(() => _shaderError = e.toString());
      },
    );
  }

  @override
  Widget build(final BuildContext context) {
    return StreamBuilder<DicomViewerState>(
      stream: widget.controller.states,
      initialData: widget.controller.state,
      builder: (final context, final snapshot) {
        final state = snapshot.data ?? widget.controller.state;
        return switch (state.status) {
          DicomViewerLoading() => widget.loadingBuilder?.call(context) ??
              const Center(child: CircularProgressIndicator()),
          DicomViewerError(:final error) =>
            widget.errorBuilder?.call(context, error) ??
                Center(
                  child: Text(
                    error.message,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
          DicomViewerIdle() => widget.emptyBuilder?.call(context) ??
              const Center(child: Text('No DICOM data loaded.')),
          DicomViewerReady() => _buildReady(context, state),
        };
      },
    );
  }

  Widget _buildReady(final BuildContext context, final DicomViewerState state) {
    if (_shaderError != null) {
      return widget.errorBuilder?.call(context, _shaderError!) ??
          Center(
            child: Text(
              _shaderError!,
              style: const TextStyle(color: Colors.red),
            ),
          );
    }
    final shader = _shader;
    final texture = widget.controller.texture;
    final pixels = widget.controller.pixels;
    final geometry = widget.controller.geometry;
    if (shader == null ||
        texture == null ||
        pixels == null ||
        geometry == null) {
      return widget.loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator());
    }
    final aspect = pixels.width / pixels.height;
    return LayoutBuilder(
      builder: (final context, final constraints) {
        final fitted = _fitContain(
          constraints.maxWidth,
          constraints.maxHeight,
          aspect,
        );
        return Center(
          child: SizedBox(
            width: fitted.width,
            height: fitted.height,
            child: GestureDetector(
              onPanUpdate: widget.windowDrag
                  ? (final details) {
                      widget.controller.setWindow(
                        state.window.copyWith(
                          center: state.window.center + details.delta.dy * 1.5,
                          width: state.window.width + details.delta.dx * 1.5,
                        ),
                      );
                    }
                  : null,
              onDoubleTap: widget.controller.reset,
              onTapDown: widget.probeInteraction
                  ? (final details) => _setProbe(details.localPosition, fitted)
                  : null,
              child: MouseRegion(
                onHover: widget.probeInteraction
                    ? (final event) => _setProbe(event.localPosition, fitted)
                    : null,
                onExit: widget.probeInteraction
                    ? (final _) => setState(() => _probeImagePoint = null)
                    : null,
                child: Stack(
                  children: [
                    CustomPaint(
                      size: Size(fitted.width, fitted.height),
                      painter: DicomImagePainter(
                        texture: texture,
                        shader: shader,
                        window: state.window,
                        slope: pixels.transform.rescaleSlope,
                        intercept: pixels.transform.rescaleIntercept,
                        invert: state.invert,
                      ),
                    ),
                    CustomPaint(
                      size: Size(fitted.width, fitted.height),
                      painter: DicomOverlaysPainter(
                        overlays: widget.overlays,
                        context: DicomOverlayContext(
                          viewport: DicomViewport(
                            width: fitted.width,
                            height: fitted.height,
                          ),
                          geometry: geometry,
                          scale: state.zoom,
                          probePoint: _probeImagePoint,
                          pixels: pixels,
                          window: state.window,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _setProbe(final Offset local, final Size fitted) {
    final pixels = widget.controller.pixels;
    if (pixels == null) return;
    final px = (local.dx / fitted.width) * pixels.width;
    final py = (local.dy / fitted.height) * pixels.height;
    if (px < 0 || py < 0 || px >= pixels.width || py >= pixels.height) {
      setState(() => _probeImagePoint = null);
      return;
    }
    setState(() => _probeImagePoint = DicomPoint(px, py));
  }

  Size _fitContain(final double maxWidth, final double maxHeight, final double aspect) {
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
}
