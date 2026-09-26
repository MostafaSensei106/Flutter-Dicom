import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dicom_overlay.dart';

/// Anatomical orientation markers derived from direction cosines.
///
/// Maps the dominant patient axis of each image edge to R/L/A/P/H/F.
/// Marker positions follow the view rotation so they stay glued to the
/// rotated anatomy. Renders nothing when orientation is unknown.
final class OrientationOverlay implements DicomOverlay {
  /// Creates an anatomical orientation marker overlay.
  const OrientationOverlay();

  @override
  void paint(final Canvas canvas, final DicomOverlayContext context) {
    final orientation = context.geometry.orientation;
    if (orientation == null) return;
    final row = _axisLetter(orientation.rowCosines);
    final col = _axisLetter(orientation.columnCosines);
    if (row == null || col == null) return;

    const margin = 12.0;
    final w = context.viewport.width;
    final h = context.viewport.height;
    // Left edge shows the negative row direction; right edge positive.
    _draw(
      canvas,
      _negate(row),
      _rotated(Offset(margin, h / 2), w, h, context.rotation),
    );
    _draw(canvas, row, _rotated(Offset(w - margin, h / 2), w, h, context.rotation));
    _draw(
      canvas,
      _negate(col),
      _rotated(Offset(w / 2, margin + 6), w, h, context.rotation),
    );
    _draw(
      canvas,
      col,
      _rotated(Offset(w / 2, h - margin - 6), w, h, context.rotation),
    );
  }

  /// Rotates [point] about the viewport center by [degrees] clockwise.
  Offset _rotated(
    final Offset point,
    final double w,
    final double h,
    final double degrees,
  ) {
    if (degrees == 0) return point;
    final rad = degrees * math.pi / 180.0;
    final cosR = math.cos(rad);
    final sinR = math.sin(rad);
    final dx = point.dx - w / 2;
    final dy = point.dy - h / 2;
    return Offset(
      w / 2 + dx * cosR - dy * sinR,
      h / 2 + dx * sinR + dy * cosR,
    );
  }

  /// Dominant patient axis of a direction cosine vector.
  String? _axisLetter(final List<double> cosines) {
    if (cosines.length < 3) return null;
    var dominant = 0;
    for (var i = 1; i < 3; i++) {
      if (cosines[i].abs() > cosines[dominant].abs()) dominant = i;
    }
    final sign = cosines[dominant] >= 0 ? 1 : -1;
    return switch ((dominant, sign)) {
      (0, 1) => 'L',
      (0, -1) => 'R',
      (1, 1) => 'P',
      (1, -1) => 'A',
      (2, 1) => 'H',
      (2, -1) => 'F',
      _ => null,
    };
  }

  String _negate(final String letter) => switch (letter) {
        'L' => 'R',
        'R' => 'L',
        'A' => 'P',
        'P' => 'A',
        'H' => 'F',
        'F' => 'H',
        _ => letter,
      };

  void _draw(final Canvas canvas, final String letter, final Offset center) {
    final span = TextSpan(
      text: letter,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(blurRadius: 4)],
      ),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }
}
