import 'package:flutter/material.dart';

import '../../analysis/dicom_ruler.dart';
import '../../domain/dicom_geometry.dart';
import 'dicom_overlay.dart';

/// Point-to-point ruler drawn through the view transform.
///
/// The line tracks zoom / pan / rotation like the image itself; the label
/// shows millimeters when pixel spacing is known, otherwise pixels.
final class RulerOverlay implements DicomOverlay {
  /// Creates a ruler from [start] to [end] in image-pixel coordinates.
  const RulerOverlay({
    required this.start,
    required this.end,
    this.ruler = const DicomRuler(),
  });

  /// Line start in image-pixel coordinates.
  final DicomPoint start;

  /// Line end in image-pixel coordinates.
  final DicomPoint end;

  /// Domain ruler computing the measurement.
  final DicomRuler ruler;

  @override
  void paint(final Canvas canvas, final DicomOverlayContext context) {
    final pixels = context.pixels;
    if (pixels == null) return;
    final a = context.transform.imageToScreen(
      start,
      context.viewport,
      pixels.width,
      pixels.height,
    );
    final b = context.transform.imageToScreen(
      end,
      context.viewport,
      pixels.width,
      pixels.height,
    );
    final aOff = Offset(a.x, a.y);
    final bOff = Offset(b.x, b.y);

    final paint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 1.5;
    canvas.drawLine(aOff, bOff, paint);
    // End ticks perpendicular to the shaft.
    final dx = bOff.dx - aOff.dx;
    final dy = bOff.dy - aOff.dy;
    final len = (dx * dx + dy * dy) <= 0
        ? 1.0
        : (dx * dx + dy * dy);
    final nx = -dy / len * 6;
    final ny = dx / len * 6;
    canvas.drawLine(
      Offset(aOff.dx - nx, aOff.dy - ny),
      Offset(aOff.dx + nx, aOff.dy + ny),
      paint,
    );
    canvas.drawLine(
      Offset(bOff.dx - nx, bOff.dy - ny),
      Offset(bOff.dx + nx, bOff.dy + ny),
      paint,
    );

    final m = ruler.measure(start, end, context.geometry);
    final label = m.millimeters != null
        ? '${m.millimeters!.toStringAsFixed(1)} mm'
        : '${m.pixelDistance.toStringAsFixed(1)} px';
    _drawLabel(canvas, label, (aOff + bOff) / 2, context.viewport.width);
  }

  void _drawLabel(
    final Canvas canvas,
    final String label,
    final Offset anchor,
    final double maxWidth,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth - 32);
    const pad = 6.0;
    final bg = Paint()..color = Colors.black87;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          anchor.dx + 8,
          anchor.dy - tp.height - pad * 2 - 4,
          tp.width + pad * 2,
          tp.height + pad * 2,
        ),
        const Radius.circular(4),
      ),
      bg,
    );
    tp.paint(canvas, Offset(anchor.dx + 8 + pad, anchor.dy - tp.height - pad - 4));
  }
}
