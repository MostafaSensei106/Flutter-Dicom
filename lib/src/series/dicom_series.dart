import '../domain/dicom_frame.dart';
import '../domain/dicom_geometry.dart';
import '../domain/dicom_source.dart';

/// Series load tuning.
final class DicomSeriesLoadOptions {
  /// Creates load options; [metadataOnly] skips pixel loading.
  const DicomSeriesLoadOptions({this.metadataOnly = false});

  /// Whether to load metadata only and skip pixel data.
  final bool metadataOnly;
}

/// An ordered stack of slices forming one series.
final class DicomSeries {
  /// Creates a series from ordered [frames] with spatial [geometry].
  const DicomSeries({required this.frames, required this.geometry});

  /// Ordered slice frames of this series.
  final List<DicomFrameReference> frames;

  /// Spatial context of the stacked slices.
  final DicomSeriesGeometry geometry;

  /// Number of slices in the series.
  int get sliceCount => frames.length;

  /// Returns the slice frame at [index].
  DicomFrameReference slice(final int index) => frames[index];

  /// File paths backing the slices, in display order.
  ///
  /// Feed this to `DicomSource.files(...)` so the viewer scrubs slices in
  /// the same spatially sorted order (stack navigation).
  List<String> get filePaths => [
        for (final f in frames)
          if (f.label != null) f.label!,
      ];
}

/// Slice ordering port — the loader never hardcodes one algorithm.
///
/// The default chain is spatial (Image Position/Orientation) with an
/// Instance Number fallback; directories without spatial tags still sort
/// deterministically instead of depending on filesystem order.
abstract interface class SeriesOrderingStrategy {
  /// Returns [frames] in display order (may return the input as-is).
  List<DicomFrameReference> sort(
    final List<DicomFrameReference> frames, {
    required final DicomOrientation? orientation,
  });

  /// Position of [frame] along the series normal, or null when unknown.
  double? slicePosition(
    final DicomFrameReference frame, {
    required final DicomOrientation? orientation,
  });
}

/// Spatial ordering by Image Position projected onto the slice normal.
///
/// Falls back per-slice to Slice Location, then Instance Number, so mixed
/// series still order deterministically.
final class SpatialSeriesOrdering implements SeriesOrderingStrategy {
  /// Creates the default spatial ordering.
  const SpatialSeriesOrdering();

  @override
  List<DicomFrameReference> sort(
    final List<DicomFrameReference> frames, {
    required final DicomOrientation? orientation,
  }) {
    if (frames.length < 2 || !_hasSpatial(frames, orientation)) {
      return List.of(frames);
    }
    final sorted = List.of(frames);
    sorted.sort((final a, final b) {
      final pa = slicePosition(a, orientation: orientation);
      final pb = slicePosition(b, orientation: orientation);
      if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
      final ia = a.instanceNumber;
      final ib = b.instanceNumber;
      if (ia != null && ib != null && ia != ib) return ia.compareTo(ib);
      return 0;
    });
    return sorted;
  }

  @override
  double? slicePosition(
    final DicomFrameReference frame, {
    required final DicomOrientation? orientation,
  }) {
    final pos = frame.position;
    if (pos != null && orientation != null) {
      final n = orientation.normal;
      return pos.x * n[0] + pos.y * n[1] + pos.z * n[2];
    }
    return frame.sliceLocation;
  }

  bool _hasSpatial(
    final List<DicomFrameReference> frames,
    final DicomOrientation? orientation,
  ) {
    if (orientation == null) return false;
    return frames.any((final f) => f.position != null);
  }
}

/// Instance Number ordering for series without spatial tags.
final class InstanceNumberOrdering implements SeriesOrderingStrategy {
  /// Creates an Instance Number ordering.
  const InstanceNumberOrdering();

  @override
  List<DicomFrameReference> sort(
    final List<DicomFrameReference> frames, {
    required final DicomOrientation? orientation,
  }) {
    if (frames.every((final f) => f.instanceNumber == null)) {
      return List.of(frames);
    }
    final sorted = List.of(frames);
    sorted.sort((final a, final b) =>
        (a.instanceNumber ?? 0).compareTo(b.instanceNumber ?? 0));
    return sorted;
  }

  @override
  double? slicePosition(
    final DicomFrameReference frame, {
    required final DicomOrientation? orientation,
  }) =>
      frame.sliceLocation;
}

/// Spatial context of a series (slice positions along the normal).
final class DicomSeriesGeometry {
  /// Creates series geometry with optional slice positions and orientation.
  const DicomSeriesGeometry({
    this.slicePositions = const [],
    this.orientation,
    this.pixelSpacing,
  });

  /// Slice positions along the series normal.
  final List<double> slicePositions;

  /// Image orientation of the series, when known.
  final DicomOrientation? orientation;

  /// In-plane pixel spacing shared by the slices, when known.
  final DicomPixelSpacing? pixelSpacing;
}

/// Series loader port — filesystem / DICOMweb adapters hide here.
abstract interface class DicomSeriesLoader {
  /// Loads a series from [source] with the given [options].
  Future<DicomSeries> load(
    final DicomSource source, {
    final DicomSeriesLoadOptions options = const DicomSeriesLoadOptions(),
  });
}
