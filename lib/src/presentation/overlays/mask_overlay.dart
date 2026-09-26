import 'package:flutter/material.dart';

import '../../advanced/dicom_advanced.dart';
import '../../domain/dicom_geometry.dart';
import 'dicom_overlay.dart';

/// Segmentation mask overlay painted through the view transform.
///
/// Row runs of set voxels merge into single rects, so dense masks cost one
/// rect per row instead of one per voxel.
final class MaskOverlay implements DicomOverlay {
  /// Creates a mask overlay with [color] and [opacity].
  const MaskOverlay({
    required this.mask,
    this.color = const Color(0xFFFF0000),
    this.opacity = 0.4,
  });

  /// Binary mask in image-pixel coordinates.
  final DicomSegmentationMask mask;

  /// Overlay tint.
  final Color color;

  /// Fill opacity in [0, 1].
  final double opacity;

  @override
  void paint(final Canvas canvas, final DicomOverlayContext context) {
    final pixels = context.pixels;
    if (pixels == null ||
        mask.width != pixels.width ||
        mask.height != pixels.height) {
      return;
    }
    if (opacity <= 0) return;
    final paint = Paint()
      ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0));
    for (var y = 0; y < mask.height; y++) {
      var x = 0;
      while (x < mask.width) {
        if (mask.data[y * mask.width + x] == 0) {
          x++;
          continue;
        }
        var x1 = x;
        while (x1 + 1 < mask.width &&
            mask.data[y * mask.width + x1 + 1] != 0) {
          x1++;
        }
        final a = context.transform.imageToScreen(
          DicomPoint(x.toDouble(), y.toDouble()),
          context.viewport,
          pixels.width,
          pixels.height,
        );
        final b = context.transform.imageToScreen(
          DicomPoint((x1 + 1).toDouble(), (y + 1).toDouble()),
          context.viewport,
          pixels.width,
          pixels.height,
        );
        canvas.drawRect(
          Rect.fromPoints(Offset(a.x, a.y), Offset(b.x, b.y)),
          paint,
        );
        x = x1 + 1;
      }
    }
  }
}
