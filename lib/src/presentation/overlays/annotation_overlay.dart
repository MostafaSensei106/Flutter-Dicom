import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../annotations/dicom_annotation.dart';
import '../../domain/dicom_geometry.dart';
import 'dicom_overlay.dart';

/// Paints every stored annotation through the view transform.
///
/// Data overlays (annotation / ruler / probe / ROI) share one rule: image
/// pixels map to screen with [DicomOverlayContext.transform], so drawings
/// stay glued to the anatomy under zoom / pan / rotation / flip.
final class AnnotationOverlay implements DicomOverlay {
  /// Creates an overlay painting [annotations].
  const AnnotationOverlay({required this.annotations});

  /// Annotations in image-pixel coordinates.
  final List<DicomAnnotation> annotations;

  @override
  void paint(final Canvas canvas, final DicomOverlayContext context) {
    final pixels = context.pixels;
    if (pixels == null) return;
    for (final annotation in annotations) {
      switch (annotation) {
        case LineAnnotation(:final start, :final end, :final style):
          canvas.drawLine(
            _map(context, start, pixels.width, pixels.height),
            _map(context, end, pixels.width, pixels.height),
            _stroke(style),
          );
        case RectangleAnnotation(:final rect, :final style):
          canvas.drawRect(
            _rect(context, rect, pixels.width, pixels.height),
            _stroke(style),
          );
        case EllipseAnnotation(:final rect, :final style):
          canvas.drawOval(
            _rect(context, rect, pixels.width, pixels.height),
            _stroke(style),
          );
        case AngleAnnotation(
            :final vertex,
            :final armA,
            :final armB,
            :final style
          ):
          final v = _map(context, vertex, pixels.width, pixels.height);
          canvas.drawLine(
            v,
            _map(context, armA, pixels.width, pixels.height),
            _stroke(style),
          );
          canvas.drawLine(
            v,
            _map(context, armB, pixels.width, pixels.height),
            _stroke(style),
          );
        case ArrowAnnotation(:final start, :final end, :final style):
          final a = _map(context, start, pixels.width, pixels.height);
          final b = _map(context, end, pixels.width, pixels.height);
          final stroke = _stroke(style);
          canvas.drawLine(a, b, stroke);
          _drawHead(canvas, a, b, stroke);
        case TextAnnotation(:final position, :final text, :final style):
          final anchor = _map(
            context,
            position,
            pixels.width,
            pixels.height,
          );
          _drawText(canvas, text, anchor, style);
        case FreehandAnnotation(:final points, :final style):
          if (points.length < 2) break;
          final path = Path();
          for (var i = 0; i < points.length; i++) {
            final p = _map(context, points[i], pixels.width, pixels.height);
            if (i == 0) {
              path.moveTo(p.dx, p.dy);
            } else {
              path.lineTo(p.dx, p.dy);
            }
          }
          canvas.drawPath(path, _stroke(style));
      }
    }
  }

  Offset _map(
    final DicomOverlayContext context,
    final DicomPoint point,
    final int imageWidth,
    final int imageHeight,
  ) {
    final s = context.transform.imageToScreen(
      point,
      context.viewport,
      imageWidth,
      imageHeight,
    );
    return Offset(s.x, s.y);
  }

  /// Axis-aligned mapping for rect/oval kinds (rotation stays a viewer
  /// concern; annotations keep their image-space shape).
  Rect _rect(
    final DicomOverlayContext context,
    final DicomRect rect,
    final int imageWidth,
    final int imageHeight,
  ) {
    final a = _map(
      context,
      DicomPoint(rect.left, rect.top),
      imageWidth,
      imageHeight,
    );
    final b = _map(
      context,
      DicomPoint(rect.left + rect.width, rect.top + rect.height),
      imageWidth,
      imageHeight,
    );
    return Rect.fromPoints(a, b);
  }

  Paint _stroke(final DicomAnnotationStyle style) => Paint()
    ..color = Color(style.color)
    ..strokeWidth = style.lineWidth
    ..style = PaintingStyle.stroke;

  void _drawHead(
    final Canvas canvas,
    final Offset tail,
    final Offset head,
    final Paint stroke,
  ) {
    final angle = math.atan2(head.dy - tail.dy, head.dx - tail.dx);
    const size = 10.0;
    const spread = 0.45;
    final p1 = Offset(
      head.dx - size * math.cos(angle - spread),
      head.dy - size * math.sin(angle - spread),
    );
    final p2 = Offset(
      head.dx - size * math.cos(angle + spread),
      head.dy - size * math.sin(angle + spread),
    );
    canvas.drawPath(Path()..moveTo(head.dx, head.dy)..lineTo(p1.dx, p1.dy)..moveTo(head.dx, head.dy)..lineTo(p2.dx, p2.dy), stroke);
  }

  void _drawText(
    final Canvas canvas,
    final String text,
    final Offset anchor,
    final DicomAnnotationStyle style,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: Color(style.color), fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, anchor);
  }
}
