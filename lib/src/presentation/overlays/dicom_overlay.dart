import 'package:flutter/material.dart';

import '../../domain/dicom_geometry.dart';
import '../../domain/dicom_pixel_data.dart';
import '../../domain/dicom_windowing.dart';

/// Overlay composite — new decorations implement [DicomOverlay] and are
/// composed by the viewer instead of adding properties to it.
///
/// ```dart
/// DicomViewer(
///   controller: controller,
///   overlays: [ScaleBarOverlay(), OrientationOverlay(), PixelProbeOverlay()],
/// )
/// ```
abstract interface class DicomOverlay {
  /// Paints the decoration onto [canvas] using [context].
  void paint(final Canvas canvas, final DicomOverlayContext context);
}

/// Read-only snapshot handed to every overlay.
final class DicomOverlayContext {
  /// Creates a read-only overlay snapshot for the current frame.
  const DicomOverlayContext({
    required this.viewport,
    required this.geometry,
    required this.scale,
    this.probePoint,
    this.pixels,
    this.window = const DicomWindow(center: 40, width: 400),
  });

  /// Viewport extents in paint pixels.
  final DicomViewport viewport;

  /// Spatial context (spacing, orientation, image dimensions).
  final DicomGeometry geometry;

  /// Current zoom scale.
  final double scale;

  /// Active probe location in image-pixel coordinates, when set.
  final DicomPoint? probePoint;

  /// Currently displayed pixels, when available.
  final DicomPixelData? pixels;

  /// Currently applied window.
  final DicomWindow window;
}

/// Base for overlays that also need a widget (tooltips, labels).
abstract interface class DicomWidgetOverlay {
  /// Builds the overlay widget for [ctx].
  Widget build(final BuildContext context, final DicomOverlayContext ctx);
}
