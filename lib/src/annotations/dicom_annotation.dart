import '../domain/dicom_geometry.dart';

/// Annotation style shared by all annotation kinds.
final class DicomAnnotationStyle {
  /// Creates an annotation style with a color and line width.
  const DicomAnnotationStyle({this.color = 0xFFFFFFFF, this.lineWidth = 2});

  /// ARGB color of the annotation stroke/text.
  final int color;

  /// Stroke width in logical pixels.
  final double lineWidth;
}

/// Closed annotation hierarchy — new kinds (e.g. `ArrowAnnotation`) extend
/// without touching the renderer, serializer, or controller.
sealed class DicomAnnotation {
  /// Creates an annotation with an [id] and rendering [style].
  const DicomAnnotation(
      {required this.id, this.style = const DicomAnnotationStyle()});

  /// Unique identifier of the annotation.
  final String id;

  /// Rendering style of the annotation.
  final DicomAnnotationStyle style;
}

/// Straight line between two image points.
final class LineAnnotation extends DicomAnnotation {
  /// Creates a line annotation from [start] to [end].
  const LineAnnotation({
    required super.id,
    required this.start,
    required this.end,
    super.style,
  });

  /// Line start in image-pixel coordinates.
  final DicomPoint start;

  /// Line end in image-pixel coordinates.
  final DicomPoint end;
}

/// Axis-aligned rectangle annotation.
final class RectangleAnnotation extends DicomAnnotation {
  /// Creates a rectangle annotation covering [rect].
  const RectangleAnnotation(
      {required super.id, required this.rect, super.style});

  /// Rectangle bounds in image-pixel coordinates.
  final DicomRect rect;
}

/// Ellipse inscribed in a bounding rectangle.
final class EllipseAnnotation extends DicomAnnotation {
  /// Creates an ellipse annotation inscribed in [rect].
  const EllipseAnnotation({required super.id, required this.rect, super.style});

  /// Bounding rectangle in image-pixel coordinates.
  final DicomRect rect;
}

/// Angle formed by two arms sharing a vertex.
final class AngleAnnotation extends DicomAnnotation {
  /// Creates an angle annotation at [vertex] with arms [armA] and [armB].
  const AngleAnnotation({
    required super.id,
    required this.vertex,
    required this.armA,
    required this.armB,
    super.style,
  });

  /// Angle vertex in image-pixel coordinates.
  final DicomPoint vertex;

  /// End of the first arm in image-pixel coordinates.
  final DicomPoint armA;

  /// End of the second arm in image-pixel coordinates.
  final DicomPoint armB;
}

/// Directed arrow from [start] to [end].
final class ArrowAnnotation extends DicomAnnotation {
  /// Creates an arrow annotation from [start] to [end].
  const ArrowAnnotation({
    required super.id,
    required this.start,
    required this.end,
    super.style,
  });

  /// Arrow tail in image-pixel coordinates.
  final DicomPoint start;

  /// Arrow head in image-pixel coordinates.
  final DicomPoint end;
}

/// Freehand polyline through image-pixel [points].
final class FreehandAnnotation extends DicomAnnotation {
  /// Creates a freehand annotation through [points].
  const FreehandAnnotation({
    required super.id,
    required this.points,
    super.style,
  });

  /// Polyline vertices in image-pixel coordinates.
  final List<DicomPoint> points;
}

/// Free text label anchored at a point.
final class TextAnnotation extends DicomAnnotation {
  /// Creates a text annotation showing [text] at [position].
  const TextAnnotation({
    required super.id,
    required this.position,
    required this.text,
    super.style,
  });

  /// Anchor position in image-pixel coordinates.
  final DicomPoint position;

  /// Label text to display.
  final String text;
}

/// Annotation controller with undo / redo history.
abstract interface class DicomAnnotationController {
  /// Currently stored annotations.
  List<DicomAnnotation> get annotations;

  /// Adds [annotation] to the store.
  void add(final DicomAnnotation annotation);

  /// Replaces the stored annotation with the same id.
  void update(final DicomAnnotation annotation);

  /// Removes the annotation with [id].
  void remove(final String id);

  /// Reverts the most recent change.
  void undo();

  /// Reapplies the most recently undone change.
  void redo();

  /// Releases resources held by the controller.
  void dispose();
}

/// In-memory annotation controller with command-stack undo / redo.
final class InMemoryDicomAnnotationController
    implements DicomAnnotationController {
  final Map<String, DicomAnnotation> _items = {};
  final List<Map<String, DicomAnnotation>> _undo = [];
  final List<Map<String, DicomAnnotation>> _redo = [];

  @override
  List<DicomAnnotation> get annotations => List.unmodifiable(_items.values);

  @override
  void add(final DicomAnnotation annotation) {
    _checkpoint();
    _items[annotation.id] = annotation;
  }

  @override
  void update(final DicomAnnotation annotation) {
    if (!_items.containsKey(annotation.id)) return;
    _checkpoint();
    _items[annotation.id] = annotation;
  }

  @override
  void remove(final String id) {
    if (!_items.containsKey(id)) return;
    _checkpoint();
    _items.remove(id);
  }

  @override
  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(Map.of(_items));
    _items
      ..clear()
      ..addAll(_undo.removeLast());
  }

  @override
  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(Map.of(_items));
    _items
      ..clear()
      ..addAll(_redo.removeLast());
  }

  void _checkpoint() {
    _undo.add(Map.of(_items));
    _redo.clear();
  }

  @override
  void dispose() {
    _items.clear();
    _undo.clear();
    _redo.clear();
  }
}
