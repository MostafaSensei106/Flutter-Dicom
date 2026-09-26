import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/dicom_geometry.dart';
import 'dicom_overlay.dart';

/// ROI shape drawn through the view transform.
///
/// Rectangle maps its four corners (a rotated view yields a polygon);
/// ellipse samples its boundary so rotation stays exact.
final class RoiOverlay implements DicomOverlay {
  /// Rectangular ROI over [bounds] in image-pixel coordinates.
  const RoiOverlay.rectangle(this.bounds) : ellipse = false;

  /// Elliptical ROI inscribed in [bounds] in image-pixel coordinates.
  const RoiOverlay.ellipse(this.bounds) : ellipse = true;

  /// Bounds in image-pixel coordinates.
  final DicomRect bounds;

  /// Whether to inscribe an ellipse instead of a rectangle.
  final bool ellipse;

  @override
  void paint(final Canvas canvas, final DicomOverlayContext context) {
    final pixels = context.pixels;
    if (pixels == null) return;
    final paint = Paint()
      ..color = Colors.limeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (!ellipse) {
      final corners = [
        DicomPoint(bounds.left, bounds.top),
        DicomPoint(bounds.left + bounds.width, bounds.top),
        DicomPoint(bounds.left + bounds.width, bounds.top + bounds.height),
        DicomPoint(bounds.left, bounds.top + bounds.height),
      ].map((final p) {
        final s = context.transform.imageToScreen(
          p,
          context.viewport,
          pixels.width,
          pixels.height,
        );
        return Offset(s.x, s.y);
      }).toList();
      canvas.drawPath(Path()..addPolygon(corners, true), paint);
      return;
    }

    final cx = bounds.left + bounds.width / 2;
    final cy = bounds.top + bounds.height / 2;
    final rx = bounds.width / 2;
    final ry = bounds.height / 2;
    final path = Path();
    for (var i = 0; i <= 48; i++) {
      final t = (i / 48) * math.pi * 2;
      final mapped = context.transform.imageToScreen(
        DicomPoint(cx + rx * math.cos(t), cy + ry * math.sin(t)),
        context.viewport,
        pixels.width,
        pixels.height,
      );
      final off = Offset(mapped.x, mapped.y);
      if (i == 0) {
        path.moveTo(off.dx, off.dy);
      } else {
        path.lineTo(off.dx, off.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }
}
