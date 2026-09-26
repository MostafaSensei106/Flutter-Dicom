import 'dart:typed_data';

import '../domain/dicom_geometry.dart';
import '../domain/dicom_pixel_data.dart';
import '../domain/dicom_windowing.dart';

/// 2D slice registration mapping CT pixels to PET sample coordinates.
///
/// Identity when both volumes share a frame of reference; translation for
/// small misalignments. Deformable registration plugs into the same port.
abstract interface class DicomSliceRegistration {
  /// Maps a CT image pixel to PET image coordinates for resampling.
  DicomPoint ctToPet(final DicomPoint ct);
}

/// Shared frame of reference: PET sampled at identical coordinates.
final class IdentitySliceRegistration implements DicomSliceRegistration {
  /// Creates an identity registration.
  const IdentitySliceRegistration();

  @override
  DicomPoint ctToPet(final DicomPoint ct) => ct;
}

/// Constant-offset registration for small misalignments.
final class TranslationSliceRegistration implements DicomSliceRegistration {
  /// Creates a translation of ([dx], [dy]) image pixels.
  const TranslationSliceRegistration(this.dx, this.dy);

  /// Horizontal offset in image pixels.
  final double dx;

  /// Vertical offset in image pixels.
  final double dy;

  @override
  DicomPoint ctToPet(final DicomPoint ct) =>
      DicomPoint(ct.x - dx, ct.y - dy);
}

/// PET pseudocolor ramp: black → red → yellow → white.
abstract final class DicomPetColorMap {
  /// Maps normalized uptake [t] in [0, 1] to RGB bytes.
  static List<int> map(final double t) {
    final c = t.clamp(0.0, 1.0);
    if (c < 0.33) {
      final k = (c / 0.33 * 255).round();
      return [k, 0, 0];
    }
    if (c < 0.66) {
      final k = ((c - 0.33) / 0.33 * 255).round();
      return [255, k, 0];
    }
    final k = ((c - 0.66) / 0.34 * 255).round();
    return [255, 255, k];
  }
}

/// CPU PET/CT fusion renderer: windowed CT grayscale blended with
/// pseudocolor PET uptake above [threshold].
///
/// PET is resampled (nearest) onto the CT grid through [registration], so
/// mismatched matrix sizes fuse without a separate resampling pass. A GPU
/// fusion backend implements the same signature later.
final class DicomFusionRenderer {
  /// Creates a fusion renderer with blend [alpha] and uptake [threshold].
  const DicomFusionRenderer({this.alpha = 0.5, this.threshold = 0.05})
      : assert(alpha >= 0 && alpha <= 1, 'alpha must be in [0, 1]');

  /// PET contribution to blended pixels.
  final double alpha;

  /// Normalized PET uptake below which CT shows through untouched.
  final double threshold;

  /// Renders [ct] fused with [pet] into an RGB frame at CT resolution.
  Future<DicomRgbPixelData> render({
    required final DicomPixelData ct,
    required final DicomWindow ctWindow,
    required final DicomPixelData pet,
    required final DicomWindow petWindow,
    final DicomSliceRegistration registration =
        const IdentitySliceRegistration(),
  }) async {
    final rgb = Uint8List(ct.width * ct.height * 3);
    for (var y = 0; y < ct.height; y++) {
      for (var x = 0; x < ct.width; x++) {
        final gray =
            (ctWindow.apply(ct.modalityAt(y * ct.width + x)) * 255).round();
        final sample = registration.ctToPet(
          DicomPoint(x.toDouble(), y.toDouble()),
        );
        final px = sample.x.round().clamp(0, pet.width - 1);
        final py = sample.y.round().clamp(0, pet.height - 1);
        final uptake = petWindow.apply(pet.modalityAt(py * pet.width + px));
        final i = (y * ct.width + x) * 3;
        if (uptake <= threshold) {
          rgb[i] = gray;
          rgb[i + 1] = gray;
          rgb[i + 2] = gray;
        } else {
          final c = DicomPetColorMap.map(uptake);
          rgb[i] = (alpha * c[0] + (1 - alpha) * gray).round();
          rgb[i + 1] = (alpha * c[1] + (1 - alpha) * gray).round();
          rgb[i + 2] = (alpha * c[2] + (1 - alpha) * gray).round();
        }
      }
    }
    return DicomRgbPixelData(buffer: rgb, width: ct.width, height: ct.height);
  }
}
