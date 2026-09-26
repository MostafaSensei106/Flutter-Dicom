import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import '../application/ports/dicom_parser.dart';
import '../application/viewer/viewer_state.dart';
import '../dicom_engine.dart';
import '../domain/dicom_color_map.dart';
import '../domain/dicom_geometry.dart';
import '../domain/dicom_pixel_data.dart';
import '../domain/dicom_source.dart';
import '../domain/dicom_windowing.dart';
import '../errors/dicom_exception.dart';
import '../infrastructure/rust/rust_dicom_parser.dart';
import 'painting.dart';

/// Viewer controller contract — reactive state in, commands out.
///
/// Implementations emit [DicomViewerState] snapshots; the widget stays dumb.
abstract interface class DicomViewerController {
  /// Current viewer snapshot.
  DicomViewerState get state;

  /// Stream of viewer snapshots.
  Stream<DicomViewerState> get states;

  /// Render model accessors used by the viewer (not part of the mutation
  /// surface, but every controller must expose what it renders).
  ///
  /// Opened document, or null before load.
  DicomDocument? get document;

  /// Currently displayed pixel data, or null before load.
  DicomPixelData? get pixels;

  /// GPU texture for the current frame, or null before load.
  ui.Image? get texture;

  /// Geometry derived from metadata and pixels, or null before load.
  DicomGeometry? get geometry;

  /// Loads [source] and shows its first frame.
  Future<void> load(final DicomSource source);

  /// Displays the frame at [index].
  Future<void> setFrame(final int index);

  /// Replaces the active windowing preset.
  void setWindow(final DicomWindow window);

  /// Applies a new color map.
  void setColorMap(final DicomColorMap colorMap);

  /// Enables or disables inversion.
  void setInvert(final bool value);

  /// Rotates the image by [degrees].
  void rotate(final double degrees);

  /// Sets the zoom factor to [scale].
  void zoom(final double scale);

  /// Pans the image by [offset].
  void pan(final DicomOffset offset);

  /// Restores default windowing, transform, and color map.
  void reset();

  /// Releases textures and state resources.
  void dispose();
}

/// Default controller wiring the Rust-backed parser to the GPU painter.
///
/// Frame textures are cached (LRU, 8 entries) so cine scrubbing never
/// re-uploads the visible stack.
final class DefaultDicomViewerController implements DicomViewerController {
  /// Creates a controller backed by an optional [parser].
  DefaultDicomViewerController({final DicomParser? parser})
      : _parser = parser ?? const RustDicomParser();

  final DicomParser _parser;
  final StreamController<DicomViewerState> _states =
      StreamController<DicomViewerState>.broadcast();
  final LinkedHashMap<int, ui.Image> _textures = LinkedHashMap();

  static const int _textureCacheCapacity = 8;

  DicomViewerState _state = const DicomViewerState();
  DicomDocument? _document;
  DicomPixelData? _pixels;
  ui.Image? _texture;

  @override
  DicomViewerState get state => _state;

  @override
  Stream<DicomViewerState> get states => _states.stream;

  @override
  DicomDocument? get document => _document;

  @override
  DicomPixelData? get pixels => _pixels;

  @override
  ui.Image? get texture => _texture;

  @override
  DicomGeometry? get geometry {
    final doc = _document;
    final pixels = _pixels;
    if (doc == null || pixels == null) return null;
    final meta = doc.metadata;
    return DicomGeometry(
      imageWidth: pixels.width,
      imageHeight: pixels.height,
      pixelSpacing: meta.pixelSpacing,
      imagerPixelSpacing: meta.imagerPixelSpacing,
      orientation: meta.imageOrientationPatient,
      position: meta.imagePositionPatient,
    );
  }

  @override
  Future<void> load(final DicomSource source) async {
    _update(_state.copyWith(status: const DicomViewerLoading()));
    try {
      final parse = await _parser.parse(source);
      _disposeTextures();
      _document = DicomDocument(metadata: parse.metadata, frames: parse.frames);
      await _showFrame(0, window: parse.metadata.defaultWindow);
      _update(
        _state.copyWith(
          status: const DicomViewerReady(),
          frameCount: parse.frameCount,
        ),
      );
    } catch (e) {
      final error = e is DicomException
          ? e
          : DicomProcessingException('Failed to load DICOM', e);
      _update(_state.copyWith(status: DicomViewerError(error)));
      rethrow;
    }
  }

  @override
  Future<void> setFrame(final int index) async {
    final doc = _document;
    if (doc == null || _state.status is! DicomViewerReady) return;
    if (index < 0 || index >= doc.frameCount || index == _state.currentFrame) {
      return;
    }
    await _showFrame(index, window: _state.window);
    _update(_state.copyWith(currentFrame: index));
  }

  Future<void> _showFrame(final int index,
      {required final DicomWindow window}) async {
    final doc = _document!;
    final frame = await doc.frames.get(index);
    final pixels = frame.pixelData;
    if (pixels == null || pixels.length == 0) {
      throw const DicomProcessingException('Frame carries no pixel data');
    }
    _pixels = pixels;
    _texture = await _cachedTexture(index, pixels);
    _update(
      _state.copyWith(
        currentFrame: index,
        window: window,
        frameCount: doc.frameCount,
      ),
    );
  }

  Future<ui.Image> _cachedTexture(
    final int index,
    final DicomPixelData pixels,
  ) async {
    final hit = _textures.remove(index);
    if (hit != null) {
      _textures[index] = hit;
      return hit;
    }
    final image = await pixelsToTexture(pixels);
    _textures[index] = image;
    while (_textures.length > _textureCacheCapacity) {
      final oldest = _textures.keys.first;
      if (oldest == index) break;
      _textures.remove(oldest)?.dispose();
    }
    return image;
  }

  @override
  void setWindow(final DicomWindow window) {
    _update(_state.copyWith(window: window));
  }

  @override
  void setColorMap(final DicomColorMap colorMap) {
    _update(_state.copyWith(colorMap: colorMap));
  }

  @override
  void setInvert(final bool value) {
    if (value == _state.invert) return;
    _update(const ToggleInvertCommand().execute(_state));
  }

  @override
  void rotate(final double degrees) {
    _update(_state.copyWith(rotation: (_state.rotation + degrees) % 360));
  }

  @override
  void zoom(final double scale) {
    if (scale <= 0) return;
    _update(_state.copyWith(zoom: scale.clamp(0.1, 32.0)));
  }

  @override
  void pan(final DicomOffset offset) {
    _update(
      _state.copyWith(
        pan: DicomOffset(
          _state.pan.dx + offset.dx,
          _state.pan.dy + offset.dy,
        ),
      ),
    );
  }

  @override
  void reset() {
    final doc = _document;
    _update(
      _state.copyWith(
        window: doc?.metadata.defaultWindow ?? _state.window,
        colorMap: DicomColorMap.grayscale,
        invert: false,
        rotation: 0,
        zoom: 1,
        pan: const DicomOffset(0, 0),
      ),
    );
  }

  void _update(final DicomViewerState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  void _disposeTextures() {
    for (final image in _textures.values) {
      image.dispose();
    }
    _textures.clear();
    _texture = null;
    _pixels = null;
  }

  @override
  void dispose() {
    _disposeTextures();
    unawaited(_states.close());
  }
}
