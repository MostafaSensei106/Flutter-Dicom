/// A single window (level / width pair) with an optional label.
final class DicomWindow {
  /// Creates a window with the given center and width.
  const DicomWindow({required this.center, required this.width, this.label})
      : assert(width > 0, 'window width must be positive');

  /// Window center (level).
  final double center;

  /// Window width.
  final double width;

  /// Optional preset label.
  final String? label;

  /// Lower bound of the window.
  double get min => center - width / 2.0;

  /// Upper bound of the window.
  double get max => center + width / 2.0;

  /// Linear windowing map of a modality value to [0, 1].
  double apply(final double value) => ((value - min) / (max - min)).clamp(0.0, 1.0);

  /// Copies this window with replaced values.
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

/// Structural source of modality for preset selection.
///
/// Implemented by [DicomMetadata]; keeps preset selection free of imports
/// that would create a domain cycle.
abstract interface class HasModality {
  /// Imaging modality, when known.
  DicomModality? get modality;
}

/// Imaging modality relevant for display defaults.
enum DicomModality {
  /// Computed tomography.
  ct,

  /// Magnetic resonance.
  mr,

  /// X-ray angiography.
  xa,

  /// Ultrasound.
  us,

  /// Computed radiography.
  cr,

  /// Digital radiography.
  dx,

  /// Mammography.
  mg,

  /// Positron emission tomography.
  pt,

  /// Nuclear medicine.
  nm,

  /// Unknown or unlisted modality.
  unknown;

  /// Parses a DICOM Modality value (0008,0060).
  static DicomModality parse(final String? raw) {
    return switch (raw?.trim().toUpperCase()) {
      'CT' => DicomModality.ct,
      'MR' => DicomModality.mr,
      'XA' => DicomModality.xa,
      'US' => DicomModality.us,
      'CR' => DicomModality.cr,
      'DX' => DicomModality.dx,
      'MG' => DicomModality.mg,
      'PT' => DicomModality.pt,
      'NM' => DicomModality.nm,
      _ => DicomModality.unknown,
    };
  }
}
/// Well-known CT presets plus modality-aware default selection.
///
/// User-defined presets live in [DicomPresetStore], not here.
abstract final class DicomWindowPreset {
  /// Brain preset (narrow soft-tissue window).
  static const brain = DicomWindow(center: 40, width: 80, label: 'Brain');
  /// Soft-tissue preset.
  static const softTissue = DicomWindow(
    center: 60,
    width: 400,
    label: 'Soft tissue',
  );
  /// Bone preset (wide high-center window).
  static const bone = DicomWindow(center: 400, width: 1800, label: 'Bone');
  /// Lung preset (negative center for air contrast).
  static const lung = DicomWindow(center: -600, width: 1500, label: 'Lung');
  /// Abdominal soft-tissue preset.
  static const abdomen = DicomWindow(center: 60, width: 400, label: 'Abdomen');

  /// All built-in presets.
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
  static DicomWindow? forImage(final HasModality image) {
    return switch (image.modality) {
      DicomModality.ct => softTissue,
      DicomModality.mr => brain,
      _ => null,
    };
  }
}

/// User-defined window preset storage (custom presets, not built-ins).
abstract interface class DicomPresetStore {
  /// Loads stored presets.
  Future<List<DicomWindow>> load();

  /// Saves [window] under [name].
  Future<void> save(final String name, final DicomWindow window);

  /// Deletes the preset named [name].
  Future<void> delete(final String name);
}

/// Strategy hook for future non-linear mappings (sigmoid / custom VOI LUT).
abstract interface class WindowingStrategy {
  /// Maps [value] through [window] to a normalized output.
  double map(final double value, final DicomWindow window);
}

/// Default linear mapping used by the GPU shader.
final class LinearWindowing implements WindowingStrategy {
  /// Creates the default linear mapping.
  const LinearWindowing();
  @override
  double map(final double value, final DicomWindow window) => window.apply(value);
}
