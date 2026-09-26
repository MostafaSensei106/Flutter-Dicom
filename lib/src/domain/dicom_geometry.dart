import 'dart:math' as math;

/// Point in any 2D DICOM coordinate space (screen / viewport / image).
final class DicomPoint {
  const DicomPoint(this.x, this.y);
  final double x;
  final double y;
}

/// Pan offset in viewport pixels.
final class DicomOffset {
  const DicomOffset(this.dx, this.dy);
  final double dx;
  final double dy;
}

/// Rectangle in image-pixel coordinates (ROI / annotations).
final class DicomRect {
  const DicomRect(this.left, this.top, this.width, this.height);
  final double left;
  final double top;
  final double width;
  final double height;
}

/// Current viewport extents handed to geometry mapping.
final class DicomViewport {
  const DicomViewport({required this.width, required this.height});
  final double width;
  final double height;
}

/// Pixel spacing in mm: (row, column).
final class DicomPixelSpacing {
  const DicomPixelSpacing(this.row, this.column);
  final double row;
  final double column;

  /// Parses DICOM `Pixel Spacing` (`"0.5\\0.5"`). `null` when absent.
  static DicomPixelSpacing? tryParse(String raw) {
    final parts = raw.split('\\');
    if (parts.length < 2) return null;
    final row = double.tryParse(parts[0].trim());
    final col = double.tryParse(parts[1].trim());
    if (row == null || col == null || row <= 0 || col <= 0) return null;
    return DicomPixelSpacing(row, col);
  }
}

/// Image orientation (0020,0037): row + column direction cosines.
final class DicomOrientation {
  const DicomOrientation({required this.rowCosines, required this.columnCosines});
  final List<double> rowCosines;
  final List<double> columnCosines;

  /// Slice normal = row × column.
  List<double> get normal {
    final r = rowCosines;
    final c = columnCosines;
    return [
      r[1] * c[2] - r[2] * c[1],
      r[2] * c[0] - r[0] * c[2],
      r[0] * c[1] - r[1] * c[0],
    ];
  }
}

/// Image position (0020,0032): top-left voxel in patient mm.
final class DicomPosition {
  const DicomPosition(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

/// Spatial context shared by probe, ruler, scale bar, orientation,
/// annotations, MPR, and fusion.
///
/// Coordinate chain: `Screen -> Viewport -> Image -> Patient`.
final class DicomGeometry {
  const DicomGeometry({
    required this.imageWidth,
    required this.imageHeight,
    this.pixelSpacing,
    this.imagerPixelSpacing,
    this.orientation,
    this.position,
  });

  final int imageWidth;
  final int imageHeight;
  final DicomPixelSpacing? pixelSpacing;
  final DicomPixelSpacing? imagerPixelSpacing;
  final DicomOrientation? orientation;
  final DicomPosition? position;

  /// Viewport tap → image pixel. `null` when outside the image.
  DicomPoint? screenToImage(DicomPoint point, DicomViewport viewport) {
    if (viewport.width <= 0 || viewport.height <= 0) return null;
    final px = (point.x / viewport.width) * imageWidth;
    final py = (point.y / viewport.height) * imageHeight;
    if (px < 0 || py < 0 || px >= imageWidth || py >= imageHeight) {
      return null;
    }
    return DicomPoint(px, py);
  }

  /// Image pixel → patient coordinates in mm. `null` without orientation.
  List<double>? imageToPatient(DicomPoint point) {
    final o = orientation;
    final p = position;
    final s = pixelSpacing ?? imagerPixelSpacing;
    if (o == null || p == null || s == null) return null;
    return [
      p.x + o.rowCosines[0] * point.x * s.column + o.columnCosines[0] * point.y * s.row,
      p.y + o.rowCosines[1] * point.x * s.column + o.columnCosines[1] * point.y * s.row,
      p.z + o.rowCosines[2] * point.x * s.column + o.columnCosines[2] * point.y * s.row,
    ];
  }

  /// Pixel distance → millimeters (column spacing as reference).
  double? pixelsToMillimeters(double pixels) {
    final s = pixelSpacing ?? imagerPixelSpacing;
    if (s == null) return null;
    return pixels * s.column;
  }
}
