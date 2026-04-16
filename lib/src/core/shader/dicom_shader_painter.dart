import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../rust/api/core/models/dicom_frame_result.dart';

/// A performance-critical [CustomPainter] that offloads medical rendering to the GPU.
///
/// `DicomShaderPainter` acts as the bridge between Flutter's Canvas and the
/// custom GLSL Fragment Shader. It handles:
/// 1. Passing current Window Center/Width to the shader.
/// 2. Binding the 16-bit packed texture.
/// 3. Passing Hounsfield Unit (HU) transformation constants.
///
/// By performing these calculations on the GPU, we ensure clinical precision
/// and smooth 60fps interactivity even on mobile devices.
class DicomShaderPainter extends CustomPainter {
  /// Creates a [DicomShaderPainter].
  DicomShaderPainter({
    required this.frameResult,
    required this.windowCenter,
    required this.windowWidth,
    required this.shader,
    required this.rawTexture,
  });

  /// The processing result containing metadata and pixel data pointers.
  final DicomFrameResult frameResult;

  /// The user-defined or default Window Center for contrast mapping.
  final double windowCenter;

  /// The user-defined or default Window Width for contrast mapping.
  final double windowWidth;

  /// The compiled GLSL shader program instance.
  final ui.FragmentShader shader;

  /// The raw 16-bit pixel data packed into an RGBA [ui.Image] sampler.
  final ui.Image rawTexture;

  /// Performs the actual drawing operation using the fragment shader.
  @override
  void paint(final Canvas canvas, final Size size) {
    // 1. Pass the canvas resolution to the shader
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);

    // 2. Pass the interactive Windowing parameters
    shader.setFloat(2, windowCenter);
    shader.setFloat(3, windowWidth);

    // 3. Pass the hardware-specific metadata for Hounsfield Units calculation
    shader.setFloat(4, frameResult.metadata.rescaleIntercept);
    shader.setFloat(5, frameResult.metadata.rescaleSlope);

    // 4. Pass the actual image texture
    shader.setImageSampler(0, rawTexture);

    // 5. Tell the GPU to paint a rectangle covering the canvas using our shader
    final paint = Paint()..shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  /// Determines if the painter needs to rebuild.
  ///
  /// Optimized to only repaint when the visual state (windowing) actually changes.
  @override
  bool shouldRepaint(covariant final DicomShaderPainter oldDelegate) {
    return oldDelegate.windowCenter != windowCenter ||
        oldDelegate.windowWidth != windowWidth ||
        oldDelegate.frameResult != frameResult;
  }
}
