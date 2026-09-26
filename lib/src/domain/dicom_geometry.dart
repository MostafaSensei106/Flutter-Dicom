import 'dart:math' as math;

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

/// View transform applied about the viewport center: flip → zoom →
/// rotation → pan (in screen pixels).
///
/// The viewer paints the image with the equivalent Flutter `Transform`
/// (`translate(pan) * rotate * scale(zoom, flip)` around center), and maps
/// pointer positions back with [screenToImage] so probe, ruler, and ROI
/// always agree with what is on screen.
final class DicomViewTransform {
  /// Creates a view transform with zoom, pan, rotation, and flip flags.
  const DicomViewTransform({
    this.zoom = 1,
    this.pan = const DicomOffset(0, 0),
    this.rotation = 0,
    this.flipH = false,
    this.flipV = false,
  });

  /// Zoom factor applied to the image.
  final double zoom;

  /// Pan offset in viewport pixels (applied after zoom/rotation).
  final DicomOffset pan;

  /// Clockwise rotation in degrees.
  final double rotation;

  /// Whether the image is mirrored horizontally.
  final bool flipH;

  /// Whether the image is mirrored vertically.
  final bool flipV;

  /// `true` when no transform is applied.
  bool get isIdentity =>
      zoom == 1 &&
      pan.dx == 0 &&
      pan.dy == 0 &&
      rotation == 0 &&
      !flipH &&
      !flipV;

  /// Viewport tap → image pixel. `null` when outside the image.
  DicomPoint? screenToImage(
    final DicomPoint screen,
    final DicomViewport viewport,
    final int imageWidth,
    final int imageHeight,
  ) {
    if (viewport.width <= 0 ||
        viewport.height <= 0 ||
        imageWidth <= 0 ||
        imageHeight <= 0 ||
        zoom <= 0) {
      return null;
    }
    final cx = viewport.width / 2;
    final cy = viewport.height / 2;
    // Undo pan + rotation + zoom + flip (reverse of imageToScreen).
    final ox = screen.x - cx - pan.dx;
    final oy = screen.y - cy - pan.dy;
    final rad = -rotation * 3.141592653589793 / 180.0;
    final cosR = _cos(rad);
    final sinR = _sin(rad);
    final rx = ox * cosR - oy * sinR;
    final ry = ox * sinR + oy * cosR;
    final ux = (flipH ? -rx : rx) / zoom;
    final uy = (flipV ? -ry : ry) / zoom;
    final baseX = ux + cx;
    final baseY = uy + cy;
    final px = (baseX / viewport.width) * imageWidth;
    final py = (baseY / viewport.height) * imageHeight;
    if (px < 0 || py < 0 || px >= imageWidth || py >= imageHeight) {
      return null;
    }
    return DicomPoint(px, py);
  }

  /// Image pixel → viewport position (always inside by construction).
  DicomPoint imageToScreen(
    final DicomPoint image,
    final DicomViewport viewport,
    final int imageWidth,
    final int imageHeight,
  ) {
    final cx = viewport.width / 2;
    final cy = viewport.height / 2;
    var ox = (image.x / imageWidth) * viewport.width - cx;
    var oy = (image.y / imageHeight) * viewport.height - cy;
    if (flipH) ox = -ox;
    if (flipV) oy = -oy;
    ox *= zoom;
    oy *= zoom;
    final rad = rotation * 3.141592653589793 / 180.0;
    final cosR = _cos(rad);
    final sinR = _sin(rad);
    final rx = ox * cosR - oy * sinR;
    final ry = ox * sinR + oy * cosR;
    return DicomPoint(rx + cx + pan.dx, ry + cy + pan.dy);
  }

  static double _cos(final double rad) {
    // Exact fast paths keep 0/90/180/270 rotations pixel-perfect.
    final deg = (rad * 180.0 / 3.141592653589793) % 360;
    final norm = deg < 0 ? deg + 360 : deg;
    if (norm == 0) return 1;
    if (norm == 180) return -1;
    if (norm == 90 || norm == 270) return 0;
    return math.cos(rad);
  }

  static double _sin(final double rad) {
    final deg = (rad * 180.0 / 3.141592653589793) % 360;
    final norm = deg < 0 ? deg + 360 : deg;
    if (norm == 0 || norm == 180) return 0;
    if (norm == 90) return 1;
    if (norm == 270) return -1;
    return math.sin(rad);
  }
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
