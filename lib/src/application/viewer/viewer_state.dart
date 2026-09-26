import '../../domain/dicom_color_map.dart';
import '../../domain/dicom_geometry.dart';
import '../../domain/dicom_windowing.dart';
import '../../errors/dicom_exception.dart';

/// Viewer lifecycle.
sealed class DicomViewerStatus {
  /// Creates a viewer status.
  const DicomViewerStatus();
}

/// Idle status before any load.
final class DicomViewerIdle extends DicomViewerStatus {
  /// Creates an idle status.
  const DicomViewerIdle();
}

/// Loading status while parsing a source.
final class DicomViewerLoading extends DicomViewerStatus {
  /// Creates a loading status.
  const DicomViewerLoading();
}

/// Ready status once the first frame is shown.
final class DicomViewerReady extends DicomViewerStatus {
  /// Creates a ready status.
  const DicomViewerReady();
}

/// Error status carrying the load failure.
final class DicomViewerError extends DicomViewerStatus {
  /// Creates an error status with [error].
  const DicomViewerError(this.error);

  /// Load failure carried by this status.
  final DicomException error;
}

/// Immutable viewer snapshot emitted to Viewer / Toolbar / Histogram.
final class DicomViewerState {
  /// Creates an immutable viewer snapshot.
  const DicomViewerState({
    this.status = const DicomViewerIdle(),
    this.currentFrame = 0,
    this.frameCount = 1,
    this.window = const DicomWindow(center: 40, width: 400),
    this.colorMap = DicomColorMap.grayscale,
    this.invert = false,
    this.rotation = 0,
    this.zoom = 1,
    this.pan = const DicomOffset(0, 0),
    this.flipH = false,
    this.flipV = false,
  });

  /// Current viewer lifecycle status.
  final DicomViewerStatus status;

  /// Index of the currently displayed frame.
  final int currentFrame;

  /// Total number of frames in the dataset.
  final int frameCount;

  /// Active windowing preset.
  final DicomWindow window;

  /// Active color map.
  final DicomColorMap colorMap;

  /// Whether monochrome output is inverted.
  final bool invert;

  /// Clockwise rotation in degrees.
  final double rotation;

  /// Zoom factor applied to the image.
  final double zoom;

  /// Pan offset applied to the image.
  final DicomOffset pan;

  /// Whether the image is mirrored horizontally.
  final bool flipH;

  /// Whether the image is mirrored vertically.
  final bool flipV;

  /// View transform composed from zoom / pan / rotation / flip state.
  DicomViewTransform get viewTransform => DicomViewTransform(
        zoom: zoom,
        pan: pan,
        rotation: rotation,
        flipH: flipH,
        flipV: flipV,
      );

  /// Returns a copy with the given fields replaced.
  DicomViewerState copyWith({
    final DicomViewerStatus? status,
    final int? currentFrame,
    final int? frameCount,
    final DicomWindow? window,
    final DicomColorMap? colorMap,
    final bool? invert,
    final double? rotation,
    final double? zoom,
    final DicomOffset? pan,
    final bool? flipH,
    final bool? flipV,
  }) =>
      DicomViewerState(
        status: status ?? this.status,
        currentFrame: currentFrame ?? this.currentFrame,
        frameCount: frameCount ?? this.frameCount,
        window: window ?? this.window,
        colorMap: colorMap ?? this.colorMap,
        invert: invert ?? this.invert,
        rotation: rotation ?? this.rotation,
        zoom: zoom ?? this.zoom,
        pan: pan ?? this.pan,
        flipH: flipH ?? this.flipH,
        flipV: flipV ?? this.flipV,
      );
}

/// Command — every viewer mutation goes through one of these so undo /
/// redo / replay can be added without touching the controller.
abstract interface class DicomViewerCommand {
  /// Executes this command against [state].
  DicomViewerState execute(final DicomViewerState state);
}

/// Sets the window center and/or width.
final class SetWindowCommand implements DicomViewerCommand {
  /// Creates a window update with optional [center] and [width].
  const SetWindowCommand({this.center, this.width});

  /// New window center, or null to keep the current one.
  final double? center;

  /// New window width, or null to keep the current one.
  final double? width;

  @override
  DicomViewerState execute(final DicomViewerState state) => state.copyWith(
        window: state.window.copyWith(center: center, width: width),
      );
}

/// Resets windowing to the dataset defaults.
final class ResetWindowCommand implements DicomViewerCommand {
  /// Creates a reset command restoring [defaults].
  const ResetWindowCommand(this.defaults);

  /// Default window restored by this command.
  final DicomWindow defaults;

  @override
  DicomViewerState execute(final DicomViewerState state) =>
      state.copyWith(window: defaults);
}

/// Selects the frame at [index].
final class SetFrameCommand implements DicomViewerCommand {
  /// Creates a frame selection for [index].
  const SetFrameCommand(this.index);

  /// Index of the frame to display.
  final int index;

  @override
  DicomViewerState execute(final DicomViewerState state) =>
      state.copyWith(currentFrame: index);
}

/// Applies a new color map.
final class SetColorMapCommand implements DicomViewerCommand {
  /// Creates a color map update for [colorMap].
  const SetColorMapCommand(this.colorMap);

  /// Color map applied by this command.
  final DicomColorMap colorMap;

  @override
  DicomViewerState execute(final DicomViewerState state) =>
      state.copyWith(colorMap: colorMap);
}

/// Toggles monochrome inversion.
final class ToggleInvertCommand implements DicomViewerCommand {
  /// Creates an inversion toggle.
  const ToggleInvertCommand();

  @override
  DicomViewerState execute(final DicomViewerState state) =>
      state.copyWith(invert: !state.invert);
}
