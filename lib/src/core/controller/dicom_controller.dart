import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../rust/api/core/config/dicom_config.dart';
import '../../rust/api/core/models/dicom_frame_result.dart';
import '../../rust/api/core/models/dicom_metadata.dart';
import '../exceptions/dicom_exceptions.dart';
import '../services/dicom_service.dart';

/// The central controller for managing DICOM file processing and rendering state.
///
/// Follows SOLID principles by using [DicomService] for actual data fetching.
class DicomController extends ChangeNotifier {

  DicomController({final DicomService? service})
      : _service = service ?? DicomService();
  final DicomService _service;

  // --- State Variables ---
  DicomFrameResult? _currentFrame;
  bool _isLoading = false;
  String? _errorMessage;
  ui.FragmentShader? _shader;
  ui.Image? _rawTexture;

  // --- Interactive State (Windowing) ---
  double? _currentWindowCenter;
  double? _currentWindowWidth;

  // --- Getters ---
  bool get isLoading => _isLoading;
  bool get hasError => _errorMessage != null;
  bool get hasData =>
      _currentFrame != null && _rawTexture != null && _shader != null;
  String? get errorMessage => _errorMessage;
  DicomMetadata? get metadata => _currentFrame?.metadata;
  DicomFrameResult? get currentFrame => _currentFrame;
  ui.Image? get rawTexture => _rawTexture;
  ui.FragmentShader? get shader => _shader;

  double? get windowCenter => _currentWindowCenter;
  double? get windowWidth => _currentWindowWidth;

  /// Initializes the controller by loading the fragment shader.
  Future<void> initialize() async {
    if (_shader != null) return;
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'packages/flutter_dicom/assets/shaders/dicom_window.frag',
      );
      _shader = program.fragmentShader();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load shader: $e';
      notifyListeners();
    }
  }

  /// Loads and processes a DICOM file from the given [filePath].
  Future<void> loadFromFile({
    required final String filePath,
    final DicomConfig? config,
  }) async {
    if (_isLoading) return;
    if (_shader == null) await initialize();

    _setLoading(true);
    _clearError();

    try {
      // Use the service to load the frame
      final result = await _service.loadFrame(filePath, config: config);
      _currentFrame = result;

      // Create GPU texture from raw pixel data
      if (result.pixelData.isNotEmpty) {
        _rawTexture = await _createTexture(
          result.pixelData,
          result.metadata.width,
          result.metadata.height,
        );
      }

      // Initialize interactive windowing values
      _currentWindowCenter = result.metadata.windowCenter;
      _currentWindowWidth = result.metadata.windowWidth;
    } catch (e) {
      _errorMessage = 'Failed to load DICOM: ${e.toString()}';
      notifyListeners();
      throw DicomProcessingException(_errorMessage!);
    } finally {
      _setLoading(false);
    }
  }

  /// Converts raw 16-bit pixel data into a Flutter-compatible ui.Image.
  /// We pack the 16-bit value into R and G channels to maintain precision.
  Future<ui.Image> _createTexture(final Int16List data, final int width, final int height) async {
    final rgbaData = Uint8List(width * height * 4);

    for (var i = 0; i < data.length; i++) {
      final val = data[i] + 32768; // Offset to make it unsigned u16
      rgbaData[i * 4 + 0] = (val >> 8) & 0xFF; // R: High byte
      rgbaData[i * 4 + 1] = val & 0xFF; // G: Low byte
      rgbaData[i * 4 + 2] = 0; // B: unused
      rgbaData[i * 4 + 3] = 255; // A: opaque
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaData,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (final ui.Image img) => completer.complete(img),
    );
    return completer.future;
  }

  /// Adjusts the Window Center and Width (Brightness & Contrast).
  void adjustWindowing({
    required final double deltaX,
    required final double deltaY,
  }) {
    if (!hasData) return;

    const sensitivity = 1.5;
    updateWindowing(
      center: _currentWindowCenter! + (deltaY * sensitivity),
      width: _currentWindowWidth! + (deltaX * sensitivity),
    );
  }

  /// Updates the Window Center and Width directly.
  void updateWindowing({final double? center, final double? width}) {
    if (!hasData) return;

    if (center != null) {
      _currentWindowCenter = center;
    }
    if (width != null) {
      _currentWindowWidth = width.clamp(1.0, 8000.0);
    }

    notifyListeners();
  }

  /// Resets the windowing values back to the original DICOM defaults.
  void resetWindowing() {
    if (!hasData) return;
    _currentWindowCenter = _currentFrame?.metadata.windowCenter;
    _currentWindowWidth = _currentFrame?.metadata.windowWidth;
    notifyListeners();
  }

  /// Clears the current data and frees up memory.
  void clear() {
    _currentFrame = null;
    _rawTexture?.dispose();
    _rawTexture = null;
    _currentWindowCenter = null;
    _currentWindowWidth = null;
    _clearError();
    notifyListeners();
  }

  @override
  void dispose() {
    _rawTexture?.dispose();
    super.dispose();
  }

  // --- Internal Helpers ---
  void _setLoading(final bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }
}
