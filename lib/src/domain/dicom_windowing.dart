/// A single window (level / width pair) with an optional label.
final class DicomWindow {
  const DicomWindow({required this.center, required this.width, this.label})
      : assert(width > 0, 'window width must be positive');

  final double center;
  final double width;
  final String? label;

  double get min => center - width / 2.0;
  double get max => center + width / 2.0;

  /// Linear windowing map of a modality value to [0, 1].
  double apply(final double value) => ((value - min) / (max - min)).clamp(0.0, 1.0);

  DicomWindow copyWith(
          {final double? center, final double? width, final String? Function()? label}) =>
      DicomWindow(
        center: center ?? this.center,
        width: (width ?? this.width).clamp(1.0, 8000.0),
        label: label != null ? label() : this.label,
      );

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      other is DicomWindow &&
          runtimeType == other.runtimeType &&
          center == other.center &&
          width == other.width &&
          label == other.label;

  @override
  int get hashCode => center.hashCode ^ width.hashCode ^ label.hashCode;
}

/// Well-known CT presets plus modality-aware default selection.
///
/// User-defined presets live in [DicomPresetStore], not here.
abstract final class DicomWindowPreset {
  static const brain = DicomWindow(center: 40, width: 80, label: 'Brain');
  static const softTissue = DicomWindow(
    center: 60,
    width: 400,
    label: 'Soft tissue',
  );
  static const bone = DicomWindow(center: 400, width: 1800, label: 'Bone');
  static const lung = DicomWindow(center: -600, width: 1500, label: 'Lung');
  static const abdomen = DicomWindow(center: 60, width: 400, label: 'Abdomen');

  static const List<DicomWindow> all = [
    brain,
    softTissue,
    bone,
    lung,
    abdomen,
  ];

  /// Legacy alias kept for existing call sites.
  static List<DicomWindow> get allWindows => all;

  /// Modality-aware default when the header carries no windowing.
  static DicomWindow? forImage(final Object metadata) {
    // Implemented against the domain metadata without importing it
    // (avoids a domain import cycle): matches on modality name.
    final modality = (metadata as dynamic).modality?.name as String?;
    return switch (modality) {
      'ct' => softTissue,
      'mr' => brain,
      _ => null,
    };
  }
}

/// User-defined window preset storage (custom presets, not built-ins).
abstract interface class DicomPresetStore {
  Future<List<DicomWindow>> load();
  Future<void> save(final String name, final DicomWindow window);
  Future<void> delete(final String name);
}

/// Strategy hook for future non-linear mappings (sigmoid / custom VOI LUT).
abstract interface class WindowingStrategy {
  double map(final double value, final DicomWindow window);
}

/// Default linear mapping used by the GPU shader.
final class LinearWindowing implements WindowingStrategy {
  const LinearWindowing();
  @override
  double map(final double value, final DicomWindow window) => window.apply(value);
}
