import 'dart:typed_data';

import '../domain/dicom_pixel_data.dart';
import '../domain/dicom_windowing.dart';
import 'dicom_voxels.dart';

/// Transfer function mapping modality values to display RGBA.
///
/// The CPU renderer below uses a windowed grayscale ramp with a linear
/// opacity ramp; GPU backends (Vulkan / Metal / fragment shader) implement
/// the same [DicomVolumeRenderer] port with richer shading.
final class DicomTransferFunction {
  /// Creates a windowed grayscale transfer function.
  const DicomTransferFunction({
    this.window = const DicomWindow(center: 40, width: 400),
    this.opacityMin = 0.0,
    this.opacityMax = 1.0,
  });

  /// Window mapping modality values to [0, 1] intensity.
  final DicomWindow window;

  /// Opacity at the window minimum.
  final double opacityMin;

  /// Opacity at the window maximum.
  final double opacityMax;

  /// Maps [modalityValue] to `(intensity, opacity)`.
  (double, double) map(final double modalityValue) {
    final t = window.apply(modalityValue);
    return (t, opacityMin + (opacityMax - opacityMin) * t);
  }
}

/// Render tuning for [DicomVolumeRenderer].
final class DicomVolumeRenderOptions {
  /// Creates render tuning with output size and transfer function.
  const DicomVolumeRenderOptions({
    this.outputWidth = 128,
    this.outputHeight = 128,
    this.transferFunction = const DicomTransferFunction(),
  }) : assert(outputWidth > 0 && outputHeight > 0);

  /// Output image width in pixels.
  final int outputWidth;

  /// Output image height in pixels.
  final int outputHeight;

  /// Value-to-RGBA mapping applied along each ray.
  final DicomTransferFunction transferFunction;
}

/// 3D volume renderer port — deliberately separate from [DicomRenderer].
///
/// 2D image rendering (windowing a decoded frame) and volume rendering
/// (resampling + compositing a voxel grid) are fundamentally different
/// pipelines; they share domain types, never implementations.
abstract interface class DicomVolumeRenderer {
  /// Renders [volume] from above (+z view) into an RGB frame.
  Future<DicomPixelData> render(
    final DicomVoxelVolume volume,
    final DicomVolumeRenderOptions options,
  );
}

/// CPU front-to-back compositor (reference implementation).
///
/// Casts one ray per output pixel along z, compositing windowed samples
/// with early ray termination. Output is interleaved RGB grayscale.
/// Resolution stays modest by default — GPU backends take over for
/// interactive rates; the port (not the pixels) is what M5 freezes.
final class CpuCompositeVolumeRenderer implements DicomVolumeRenderer {
  /// Creates a CPU reference renderer.
  const CpuCompositeVolumeRenderer();

  @override
  Future<DicomPixelData> render(
    final DicomVoxelVolume volume,
    final DicomVolumeRenderOptions options,
  ) async {
    final ow = options.outputWidth;
    final oh = options.outputHeight;
    final tf = options.transferFunction;
    final rgb = Uint8List(ow * oh * 3);
    for (var oy = 0; oy < oh; oy++) {
      for (var ox = 0; ox < ow; ox++) {
        // Nearest source voxel for this output pixel.
        final sx = ((ox + 0.5) / ow * volume.width).floor().clamp(
              0,
              volume.width - 1,
            );
        final sy = ((oy + 0.5) / oh * volume.height).floor().clamp(
              0,
              volume.height - 1,
            );
        var acc = 0.0; // accumulated intensity
        var transmittance = 1.0; // remaining light
        for (var z = 0; z < volume.depth; z++) {
          final modality = volume.modalityAt(sx, sy, z);
          final (intensity, opacity) = tf.map(modality);
          acc += transmittance * opacity * intensity;
          transmittance *= 1 - opacity;
          if (transmittance < 0.01) break; // early ray termination
        }
        final gray = (acc.clamp(0.0, 1.0) * 255).round();
        final i = (oy * ow + ox) * 3;
        rgb[i] = gray;
        rgb[i + 1] = gray;
        rgb[i + 2] = gray;
      }
    }
    return DicomRgbPixelData(
      buffer: rgb,
      width: ow,
      height: oh,
    );
  }
}
