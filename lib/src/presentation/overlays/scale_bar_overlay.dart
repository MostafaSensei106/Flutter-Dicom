import 'package:flutter/material.dart';

import 'dicom_overlay.dart';

/// Physical scale bar drawn from pixel spacing.
///
/// Chooses the largest "nice" length (1/5/10/50/100/500 mm) fitting ~40%
/// of the viewport width. Renders nothing when spacing is unknown.
final class ScaleBarOverlay implements DicomOverlay {
  const ScaleBarOverlay();

  static const _candidates = [1.0, 5.0, 10.0, 50.0, 100.0, 500.0];

  @override
  void paint(final Canvas canvas, final DicomOverlayContext context) {
    final spacing =
        context.geometry.pixelSpacing ?? context.geometry.imagerPixelSpacing;
    if (spacing == null) return;
    final physicalWidthMm = context.geometry.imageWidth * spacing.column;
    if (physicalWidthMm <= 0) return;
    final pixelsPerMm =
        (context.viewport.width * context.scale) / physicalWidthMm;

    var chosen = _candidates.first;
    for (final length in _candidates.reversed) {
      if (length * pixelsPerMm < context.viewport.width * 0.4) {
        chosen = length;
        break;
      }
    }
    final barWidth = chosen * pixelsPerMm;
    if (barWidth < 8) return;

    const margin = 16.0;
    final y = context.viewport.height - margin;
    final x1 = context.viewport.width - margin - barWidth;
    final x2 = context.viewport.width - margin;

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x1, y), Offset(x2, y), paint);
    canvas.drawLine(Offset(x1, y - 3), Offset(x1, y + 3), paint);
    canvas.drawLine(Offset(x2, y - 3), Offset(x2, y + 3), paint);

    final label = '${chosen.toInt()} mm';
    final span = TextSpan(
      text: label,
      style: const TextStyle(color: Colors.white, fontSize: 12),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x2 - tp.width, y - tp.height - 6));
  }
}
