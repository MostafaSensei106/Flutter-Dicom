/// Point in any 2D DICOM coordinate space (screen / viewport / image).
final class DicomPoint {
  /// Creates a point at ([x], [y]).
  const DicomPoint(this.x, this.y);

  /// Horizontal coordinate.
  final double x;

  /// Vertical coordinate.
  final double y;
}

/// Pan offset in viewport pixels.
final class DicomOffset {
  /// Creates an offset of ([dx], [dy]).
  const DicomOffset(this.dx, this.dy);

  /// Horizontal offset.
  final double dx;

  /// Vertical offset.
  final double dy;
}

/// Rectangle in image-pixel coordinates (ROI / annotations).
final class DicomRect {
  /// Creates a rectangle with the given bounds.
  const DicomRect(this.left, this.top, this.width, this.height);

  /// Left edge in pixels.
  final double left;

  /// Top edge in pixels.
  final double top;

  /// Width in pixels.
  final double width;

  /// Height in pixels.
  final double height;
}

/// Current viewport extents handed to geometry mapping.
final class DicomViewport {
  /// Creates a viewport with the given extents.
  const DicomViewport({required this.width, required this.height});

  /// Viewport width in pixels.
  final double width;

  /// Viewport height in pixels.
  final double height;
}

/// Pixel spacing in mm: (row, column).
final class DicomPixelSpacing {
  /// Creates pixel spacing in mm.
  const DicomPixelSpacing(this.row, this.column);

  /// Row spacing in mm.
  final double row;

  /// Column spacing in mm.
  final double column;

  /// Parses DICOM `Pixel Spacing` (`"0.5\\0.5"`). `null` when absent.
  static DicomPixelSpacing? tryParse(final String raw) {
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
  /// Creates orientation from direction cosines.
  const DicomOrientation(
      {required this.rowCosines, required this.columnCosines});

  /// Row direction cosines.
  final List<double> rowCosines;

  /// Column direction cosines.
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
  /// Creates a patient-space position.
  const DicomPosition(this.x, this.y, this.z);

  /// X coordinate in mm.
  final double x;

  /// Y coordinate in mm.
  final double y;

  /// Z coordinate in mm.
  final double z;
}

/// Spatial context shared by probe, ruler, scale bar, orientation,
/// annotations, MPR, and fusion.
///
/// Coordinate chain: `Screen -> Viewport -> Image -> Patient`.
final class DicomGeometry {
  /// Creates spatial context for an image.
  const DicomGeometry({
    required this.imageWidth,
    required this.imageHeight,
    this.pixelSpacing,
    this.imagerPixelSpacing,
    this.orientation,
    this.position,
  });

  /// Image width in pixels.
  final int imageWidth;

  /// Image height in pixels.
  final int imageHeight;

  /// Pixel Spacing (0028,0030), when present.
  final DicomPixelSpacing? pixelSpacing;

  /// Imager Pixel Spacing (0018,1164), when present.
  final DicomPixelSpacing? imagerPixelSpacing;

  /// Image orientation (0020,0037), when present.
  final DicomOrientation? orientation;

  /// Image position (0020,0032), when present.
  final DicomPosition? position;

  /// Viewport tap → image pixel. `null` when outside the image.
  DicomPoint? screenToImage(
      final DicomPoint point, final DicomViewport viewport) {
    if (viewport.width <= 0 || viewport.height <= 0) return null;
    final px = (point.x / viewport.width) * imageWidth;
    final py = (point.y / viewport.height) * imageHeight;
    if (px < 0 || py < 0 || px >= imageWidth || py >= imageHeight) {
      return null;
    }
    return DicomPoint(px, py);
  }

  /// Image pixel → patient coordinates in mm. `null` without orientation.
  List<double>? imageToPatient(final DicomPoint point) {
    final o = orientation;
    final p = position;
    final s = pixelSpacing ?? imagerPixelSpacing;
    if (o == null || p == null || s == null) return null;
    return [
      p.x +
          o.rowCosines[0] * point.x * s.column +
          o.columnCosines[0] * point.y * s.row,
      p.y +
          o.rowCosines[1] * point.x * s.column +
          o.columnCosines[1] * point.y * s.row,
      p.z +
          o.rowCosines[2] * point.x * s.column +
          o.columnCosines[2] * point.y * s.row,
    ];
  }

  /// Pixel distance → millimeters (column spacing as reference).
  double? pixelsToMillimeters(final double pixels) {
    final s = pixelSpacing ?? imagerPixelSpacing;
    if (s == null) return null;
    return pixels * s.column;
  }
}
