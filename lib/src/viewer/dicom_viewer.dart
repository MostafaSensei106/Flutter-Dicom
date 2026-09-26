import 'dart:async';
import 'dart:math' as math;
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
  /// Creates a dumb DICOM viewer driven by [controller].
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

  /// Controller owning viewer state and textures.
  final DicomViewerController controller;

  /// Builder for the loading state.
  final Widget Function(BuildContext context)? loadingBuilder;

  /// Builder for the error state.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// Builder for the empty state.
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

  // Gesture disambiguation: one pointer drives windowing, two drive
  // zoom / pan / rotation. Pointer counting is manual so behavior does
  // not depend on per-version ScaleDetails fields.
  int _pointers = 0;
  double _baseZoom = 1;
  double _lastRotation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(
      loadDicomShader().then(
        (final shader) {
          if (mounted) setState(() => _shader = shader);
        },
        onError: (final Object e) {
          if (mounted) setState(() => _shaderError = e.toString());
        },
      ),
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
            child: Listener(
              onPointerDown: (final _) {
                _pointers++;
                if (_pointers == 2) {
                  _baseZoom = state.zoom;
                  _lastRotation = 0;
                }
              },
              onPointerUp: (final _) {
                _pointers = (_pointers - 1).clamp(0, 10);
              },
              onPointerCancel: (final _) {
                _pointers = (_pointers - 1).clamp(0, 10);
              },
              child: GestureDetector(
                onScaleStart: (final _) {
                  _baseZoom = state.zoom;
                  _lastRotation = 0;
                },
                onScaleUpdate: (final details) =>
                    _onScaleUpdate(details, state),
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
                      Transform(
                        alignment: Alignment.center,
                        // ignore: deprecated_member_use
                        transform: Matrix4.identity()
                          // ignore: deprecated_member_use
                          ..translate(
                            state.pan.dx,
                            state.pan.dy,
                          )
                          ..rotateZ(state.rotation * math.pi / 180.0)
                          // ignore: deprecated_member_use
                          ..scale(
                            state.zoom * (state.flipH ? -1 : 1),
                            state.zoom * (state.flipV ? -1 : 1),
                          ),
                        child: CustomPaint(
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
                            rotation: state.rotation,
                            pan: state.pan,
                            flipH: state.flipH,
                            flipV: state.flipV,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onScaleUpdate(
    final ScaleUpdateDetails details,
    final DicomViewerState state,
  ) {
    if (_pointers <= 1) {
      // Single-pointer drag adjusts windowing (horizontal → width,
      // vertical → center), matching the clinical convention.
      if (!widget.windowDrag) return;
      widget.controller.setWindow(
        state.window.copyWith(
          center: state.window.center + details.focalPointDelta.dy * 1.5,
          width: state.window.width + details.focalPointDelta.dx * 1.5,
        ),
      );
      return;
    }
    widget.controller.zoom(_baseZoom * details.scale);
    widget.controller.pan(
      DicomOffset(
        details.focalPointDelta.dx,
        details.focalPointDelta.dy,
      ),
    );
    final deltaRotation = details.rotation - _lastRotation;
    _lastRotation = details.rotation;
    if (deltaRotation != 0) {
      // ScaleDetails.rotation is in radians; state keeps clockwise degrees.
      widget.controller.rotate(deltaRotation * 180.0 / math.pi);
    }
  }

  void _setProbe(final Offset local, final Size fitted) {
    final pixels = widget.controller.pixels;
    if (pixels == null) return;
    final imagePoint = widget.controller.state.viewTransform.screenToImage(
      DicomPoint(local.dx, local.dy),
      DicomViewport(width: fitted.width, height: fitted.height),
      pixels.width,
      pixels.height,
    );
    setState(() => _probeImagePoint = imagePoint);
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
}
