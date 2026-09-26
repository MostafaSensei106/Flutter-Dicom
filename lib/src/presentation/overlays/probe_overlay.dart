import 'package:flutter/material.dart';

import '../../analysis/dicom_probe.dart';
import 'dicom_overlay.dart';

/// Pixel probe marker + readout painted at the active probe point.
///
/// Probing is pure domain logic ([DicomProbe]); this overlay only draws the
/// crosshair and the HU readout box. Renders nothing without a probe point.
final class PixelProbeOverlay implements DicomOverlay {
  const PixelProbeOverlay({this.probe = const ModalityProbe()});

  final DicomProbe probe;

  @override
  void paint(Canvas canvas, DicomOverlayContext context) {
    final point = context.probePoint;
    final pixels = context.pixels;
    if (point == null || pixels == null) return;

    final scaleX = context.viewport.width / pixels.width;
    final scaleY = context.viewport.height / pixels.height;
    final dx = point.x * scaleX;
    final dy = point.y * scaleY;

    final marker = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(dx, dy), 6, marker);
    canvas.drawLine(Offset(dx - 10, dy), Offset(dx + 10, dy), marker);
    canvas.drawLine(Offset(dx, dy - 10), Offset(dx, dy + 10), marker);

    final result = probe.probe(pixels, point);
    final text = 'HU ${result.hu?.toStringAsFixed(0) ?? '—'}'
        '  (${point.x.toInt()}, ${point.y.toInt()})';
    final span = TextSpan(
      text: text,
      style: const TextStyle(color: Colors.white, fontSize: 12),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: context.viewport.width - 32);

    const pad = 6.0;
    var bx = dx + 12;
    var by = dy + 12;
    final boxW = tp.width + pad * 2;
    final boxH = tp.height + pad * 2;
    if (bx + boxW > context.viewport.width - 8) bx = dx - boxW - 12;
    if (by + boxH > context.viewport.height - 8) by = dy - boxH - 12;

    final bg = Paint()..color = Colors.black87;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, by, boxW, boxH),
        const Radius.circular(4),
      ),
      bg,
    );
    tp.paint(canvas, Offset(bx + pad, by + pad));
  }
}
