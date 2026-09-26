import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/dicom_pixel_data.dart';
import '../domain/dicom_windowing.dart';
import '../errors/dicom_exception.dart';
import '../presentation/overlays/dicom_overlay.dart';

/// Shader asset bundled with the package.
const String kDicomShaderAsset =
    'packages/flutter_dicom/assets/shaders/dicom_window.frag';

ui.FragmentShader? _cachedShader;

/// Loads (and caches) the windowing fragment shader.
Future<ui.FragmentShader> loadDicomShader() async {
  final cached = _cachedShader;
  if (cached != null) return cached;
  try {
    final program = await ui.FragmentProgram.fromAsset(kDicomShaderAsset);
    return _cachedShader = program.fragmentShader();
  } catch (e) {
    throw DicomShaderException('Failed to load windowing shader: $e');
  }
}

/// Packs decoded pixels into a GPU RGBA texture.
///
/// 16-bit integrity is preserved by splitting each value across R (high)
/// and G (low); the shader reconstructs the stored value. Color frames are
/// reduced to luminance for the monochrome pipeline.
Future<ui.Image> pixelsToTexture(final DicomPixelData pixels) {
  final width = pixels.width;
  final height = pixels.height;
  if (width <= 0 || height <= 0) {
    throw const DicomConfigurationException('Invalid image dimensions');
  }
  final count = width * height;
  final stored = Int16List(count);
  switch (pixels) {
    case DicomInt16PixelData(:final buffer):
      if (buffer.length < count) {
        throw const DicomConfigurationException('Truncated pixel buffer');
      }
      stored.setRange(0, count, buffer);
    case DicomUint8PixelData(:final buffer):
      if (buffer.length < count) {
        throw const DicomConfigurationException('Truncated pixel buffer');
      }
      for (var i = 0; i < count; i++) {
        stored[i] = buffer[i];
      }
    case DicomRgbPixelData(:final buffer):
      if (buffer.length < count * 3) {
        throw const DicomConfigurationException('Truncated pixel buffer');
      }
      for (var i = 0; i < count; i++) {
        stored[i] = (0.299 * buffer[i * 3] +
                0.587 * buffer[i * 3 + 1] +
                0.114 * buffer[i * 3 + 2])
            .round();
      }
    case DicomUint16PixelData(:final buffer):
      if (buffer.length < count) {
        throw const DicomConfigurationException('Truncated pixel buffer');
      }
      for (var i = 0; i < count; i++) {
        stored[i] = (buffer[i] - 32768).clamp(-32768, 32767);
      }
    case DicomFloat32PixelData(:final buffer):
      if (buffer.length < count) {
        throw const DicomConfigurationException('Truncated pixel buffer');
      }
      var min = double.infinity;
      var max = double.negativeInfinity;
      for (var i = 0; i < count; i++) {
        final v = buffer[i];
        if (v < min) min = v;
        if (v > max) max = v;
      }
      final range = (max - min) <= 0 ? 1.0 : (max - min);
      for (var i = 0; i < count; i++) {
        stored[i] = (((buffer[i] - min) / range) * 65535 - 32768)
            .round()
            .clamp(-32768, 32767);
      }
  }

  final rgba = Uint8List(count * 4);
  for (var i = 0; i < count; i++) {
    final val = stored[i] + 32768;
    rgba[i * 4] = (val >> 8) & 0xFF;
    rgba[i * 4 + 1] = val & 0xFF;
    rgba[i * 4 + 2] = 0;
    rgba[i * 4 + 3] = 255;
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    (final ui.Image image) => completer.complete(image),
  );
  return completer.future;
}

/// GPU painter applying windowing + rescale + inversion.
final class DicomImagePainter extends CustomPainter {
  DicomImagePainter({
    required this.texture,
    required this.shader,
    required this.window,
    required this.slope,
    required this.intercept,
    required this.invert,
  });

  final ui.Image texture;
  final ui.FragmentShader shader;
  final DicomWindow window;
  final double slope;
  final double intercept;
  final bool invert;

  @override
  void paint(final Canvas canvas, final Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, window.center)
      ..setFloat(3, window.width)
      ..setFloat(4, intercept)
      ..setFloat(5, slope)
      ..setFloat(6, invert ? 1.0 : 0.0)
      ..setImageSampler(0, texture);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant final DicomImagePainter oldDelegate) {
    return oldDelegate.texture != texture ||
        oldDelegate.window != window ||
        oldDelegate.invert != invert ||
        oldDelegate.slope != slope ||
        oldDelegate.intercept != intercept;
  }
}

/// Paints every composed overlay over the rendered image.
final class DicomOverlaysPainter extends CustomPainter {
  DicomOverlaysPainter({
    required this.overlays,
    required this.context,
  });

  final List<DicomOverlay> overlays;
  final DicomOverlayContext context;

  @override
  void paint(final Canvas canvas, final Size size) {
    for (final overlay in overlays) {
      overlay.paint(canvas, context);
    }
  }

  @override
  bool shouldRepaint(covariant final DicomOverlaysPainter oldDelegate) {
    return oldDelegate.overlays != overlays || oldDelegate.context != context;
  }
}
