import '../../errors/dicom_exception.dart';
import '../../domain/dicom_color_map.dart';
import '../../domain/dicom_geometry.dart';
import '../../domain/dicom_windowing.dart';

/// Viewer lifecycle.
sealed class DicomViewerStatus {
  const DicomViewerStatus();
}

final class DicomViewerIdle extends DicomViewerStatus {
  const DicomViewerIdle();
}

final class DicomViewerLoading extends DicomViewerStatus {
  const DicomViewerLoading();
}

final class DicomViewerReady extends DicomViewerStatus {
  const DicomViewerReady();
}

final class DicomViewerError extends DicomViewerStatus {
  const DicomViewerError(this.error);
  final DicomException error;
}

/// Immutable viewer snapshot emitted to Viewer / Toolbar / Histogram.
final class DicomViewerState {
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
  });

  final DicomViewerStatus status;
  final int currentFrame;
  final int frameCount;
  final DicomWindow window;
  final DicomColorMap colorMap;
  final bool invert;
  final double rotation;
  final double zoom;
  final DicomOffset pan;

  DicomViewerState copyWith({
    DicomViewerStatus? status,
    int? currentFrame,
    int? frameCount,
    DicomWindow? window,
    DicomColorMap? colorMap,
    bool? invert,
    double? rotation,
    double? zoom,
    DicomOffset? pan,
  }) => DicomViewerState(
    status: status ?? this.status,
    currentFrame: currentFrame ?? this.currentFrame,
    frameCount: frameCount ?? this.frameCount,
    window: window ?? this.window,
    colorMap: colorMap ?? this.colorMap,
    invert: invert ?? this.invert,
    rotation: rotation ?? this.rotation,
    zoom: zoom ?? this.zoom,
    pan: pan ?? this.pan,
  );
}

/// Command — every viewer mutation goes through one of these so undo /
/// redo / replay can be added without touching the controller.
abstract interface class DicomViewerCommand {
  DicomViewerState execute(DicomViewerState state);
}

final class SetWindowCommand implements DicomViewerCommand {
  const SetWindowCommand({this.center, this.width});
  final double? center;
  final double? width;

  @override
  DicomViewerState execute(DicomViewerState state) => state.copyWith(
    window: state.window.copyWith(center: center, width: width),
  );
}

final class ResetWindowCommand implements DicomViewerCommand {
  const ResetWindowCommand(this.defaults);
  final DicomWindow defaults;

  @override
  DicomViewerState execute(DicomViewerState state) =>
      state.copyWith(window: defaults);
}

final class SetFrameCommand implements DicomViewerCommand {
  const SetFrameCommand(this.index);
  final int index;

  @override
  DicomViewerState execute(DicomViewerState state) =>
      state.copyWith(currentFrame: index);
}

final class SetColorMapCommand implements DicomViewerCommand {
  const SetColorMapCommand(this.colorMap);
  final DicomColorMap colorMap;

  @override
  DicomViewerState execute(DicomViewerState state) =>
      state.copyWith(colorMap: colorMap);
}

final class ToggleInvertCommand implements DicomViewerCommand {
  const ToggleInvertCommand();

  @override
  DicomViewerState execute(DicomViewerState state) =>
      state.copyWith(invert: !state.invert);
}
