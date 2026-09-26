import 'dart:collection';

/// Frame cache abstraction — the controller depends on this interface,
/// never on `Map<int, Frame>` directly.
abstract interface class DicomFrameCache<T> {
  T? get(final int index);
  void put(final int index, final T frame);
  void evict(final int index);
  void clear();
  int get length;
}

/// No caching (memory-constrained devices, tests).
final class NoOpFrameCache<T> implements DicomFrameCache<T> {
  @override
  T? get(final int index) => null;
  @override
  void put(final int index, final T frame) {}
  @override
  void evict(final int index) {}
  @override
  void clear() {}
  @override
  int get length => 0;
}

/// Bounded LRU cache for cine / stack scrubbing.
final class LruFrameCache<T> implements DicomFrameCache<T> {
  LruFrameCache({this.capacity = 8}) : assert(capacity > 0);

  final int capacity;
  final LinkedHashMap<int, T> _entries = LinkedHashMap();

  @override
  T? get(final int index) {
    final value = _entries.remove(index);
    if (value == null) return null;
    _entries[index] = value; // mark most-recently-used
    return value;
  }

  @override
  void put(final int index, final T frame) {
    _entries.remove(index);
    _entries[index] = frame;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  @override
  void evict(final int index) => _entries.remove(index);

  @override
  void clear() => _entries.clear();

  @override
  int get length => _entries.length;
}
