import '../domain/dicom_geometry.dart';

/// Annotation style shared by all annotation kinds.
final class DicomAnnotationStyle {
  const DicomAnnotationStyle({this.color = 0xFFFFFFFF, this.lineWidth = 2});
  final int color;
  final double lineWidth;
}

/// Closed annotation hierarchy — new kinds (e.g. `ArrowAnnotation`) extend
/// without touching the renderer, serializer, or controller.
sealed class DicomAnnotation {
  const DicomAnnotation({required this.id, this.style = const DicomAnnotationStyle()});
  final String id;
  final DicomAnnotationStyle style;
}

final class LineAnnotation extends DicomAnnotation {
  const LineAnnotation({
    required super.id,
    required this.start,
    required this.end,
    super.style,
  });
  final DicomPoint start;
  final DicomPoint end;
}

final class RectangleAnnotation extends DicomAnnotation {
  const RectangleAnnotation({required super.id, required this.rect, super.style});
  final DicomRect rect;
}

final class EllipseAnnotation extends DicomAnnotation {
  const EllipseAnnotation({required super.id, required this.rect, super.style});
  final DicomRect rect;
}

final class AngleAnnotation extends DicomAnnotation {
  const AngleAnnotation({
    required super.id,
    required this.vertex,
    required this.armA,
    required this.armB,
    super.style,
  });
  final DicomPoint vertex;
  final DicomPoint armA;
  final DicomPoint armB;
}

final class TextAnnotation extends DicomAnnotation {
  const TextAnnotation({
    required super.id,
    required this.position,
    required this.text,
    super.style,
  });
  final DicomPoint position;
  final String text;
}

/// Annotation controller with undo / redo history.
abstract interface class DicomAnnotationController {
  List<DicomAnnotation> get annotations;
  void add(DicomAnnotation annotation);
  void update(DicomAnnotation annotation);
  void remove(String id);
  void undo();
  void redo();
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
  void add(DicomAnnotation annotation) {
    _checkpoint();
    _items[annotation.id] = annotation;
  }

  @override
  void update(DicomAnnotation annotation) {
    if (!_items.containsKey(annotation.id)) return;
    _checkpoint();
    _items[annotation.id] = annotation;
  }

  @override
  void remove(String id) {
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
