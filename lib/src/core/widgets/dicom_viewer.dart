import 'package:flutter/material.dart';
import 'package:flutter_dicom/src/core/controller/dicom_controller.dart';
import 'package:flutter_dicom/src/core/shader/dicom_shader_painter.dart';

/// A highly optimized, interactive widget for rendering DICOM images.
///
/// This widget listens to a [DicomController] and automatically handles:
/// * Loading indicators
/// * Error states
/// * Smooth Pan & Zoom via [InteractiveViewer]
/// * Real-time Windowing (Contrast/Brightness) via Drag Gestures.
class DicomViewer extends StatelessWidget {
  const DicomViewer({
    super.key,
    required this.controller,
    this.fit = BoxFit.contain,
  });

  final DicomController controller;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder ensures only this widget rebuilds when state changes
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.hasError) {
          return Center(
            child: Text(
              controller.errorMessage ?? 'Unknown error',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        if (!controller.hasData) {
          return const Center(child: Text('No DICOM data loaded.'));
        }

        // The core interactive area
        return ClipRect(
          child: GestureDetector(
            // Handle Windowing adjustments (Drag up/down, left/right)
            onPanUpdate: (details) {
              controller.adjustWindowing(
                deltaX: details.delta.dx,
                deltaY: details.delta.dy,
              );
            },
            onDoubleTap: controller.resetWindowing, // Reset on double tap
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 10.0,
              panEnabled: true,
              scaleEnabled: true,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                // The actual Native Renderer using Fragment Shaders
                child: CustomPaint(
                  painter: DicomShaderPainter(
                    frameResult: controller.currentFrame!,
                    windowCenter: controller.windowCenter!,
                    windowWidth: controller.windowWidth!,
                    shader: controller.shader!,
                    rawTexture: controller.rawTexture!,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
