import 'package:flutter/material.dart';
import '../controller/dicom_controller.dart';
import '../shader/dicom_shader_painter.dart';

/// A highly optimized, interactive widget for rendering DICOM images.
///
/// This widget listens to a [DicomController] and automatically handles:
/// * Loading indicators
/// * Error states
/// * Smooth Pan & Zoom via [InteractiveViewer]
/// * Real-time Windowing (Contrast/Brightness) via Drag Gestures.
class DicomViewer extends StatelessWidget {
  const DicomViewer({
    required this.controller, super.key,
    this.fit = BoxFit.contain,
  });

  final DicomController controller;
  final BoxFit fit;

  @override
  Widget build(final BuildContext context) {
    // ListenableBuilder ensures only this widget rebuilds when state changes
    return ListenableBuilder(
      listenable: controller,
      builder: (final context, final _) {
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
            onPanUpdate: (final details) {
              controller.adjustWindowing(
                deltaX: details.delta.dx,
                deltaY: details.delta.dy,
              );
            },
            onDoubleTap: controller.resetWindowing, // Reset on double tap
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 10.0,
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
