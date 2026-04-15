import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_dicom/src/rust/api/core/models/dicom_frame_result.dart';

/// A highly optimized CustomPainter that delegates DICOM rendering to the GPU.
///
/// It uses a Flutter FragmentShader to apply medical Windowing (Level/Width)
/// in real-time at 60fps without burdening the CPU.
class DicomShaderPainter extends CustomPainter {
  final DicomFrameResult frameResult;
  final double windowCenter;
  final double windowWidth;

  /// The compiled GLSL shader program
  final ui.FragmentShader shader;

  /// The raw 16-bit pixel data converted to a grayscale [ui.Image] texture
  final ui.Image rawTexture;

  DicomShaderPainter({
    required this.frameResult,
    required this.windowCenter,
    required this.windowWidth,
    required this.shader,
    required this.rawTexture,
  });

  @override
  void paint(Canvas canvas, Size size) {
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

  @override
  bool shouldRepaint(covariant DicomShaderPainter oldDelegate) {
    // Only repaint if the windowing (contrast/brightness) changes,
    // or if a completely new frame is loaded.
    return oldDelegate.windowCenter != windowCenter ||
        oldDelegate.windowWidth != windowWidth ||
        oldDelegate.frameResult != frameResult;
  }
}
