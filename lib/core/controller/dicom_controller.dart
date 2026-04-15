import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_dicom/core/exceptions/dicom_exceptions.dart';
import 'package:flutter_dicom/src/rust/api/core/config/dicom_config.dart';
import 'package:flutter_dicom/src/rust/api/core/models/dicom_frame_result.dart';
import 'package:flutter_dicom/src/rust/api/core/models/dicom_metadata.dart';
import 'package:flutter_dicom/src/rust/api/init.dart';

/// The central controller for managing DICOM file processing and rendering state.
///
/// This controller acts as the bridge between the Flutter UI and the high-performance
/// Rust processing engine. It holds the image data, metadata, and manages the
/// interactive windowing (contrast/brightness) state.
///
/// ### Example Usage:
/// ```dart
///  // 1. Initialize the controller
///  final dicomController = DicomController();
///
///  // 2. Load a file manually (if you just need metadata)
///  await dicomController.loadFromFile('/path/to/scan.dcm');
///  print(dicomController.metadata?.patientName);
///
///  // 3. Pass it to the UI Widget for interactive rendering
///  DicomViewer(controller: dicomController);
/// ```
class DicomController extends ChangeNotifier {
  // --- State Variables ---
  DicomFrameResult? _currentFrame;
  bool _isLoading = false;
  String? _errorMessage;

  // --- Interactive State (Windowing) ---
  double? _currentWindowCenter;
  double? _currentWindowWidth;

  // --- Getters ---
  bool get isLoading => _isLoading;
  bool get hasError => _errorMessage != null;
  bool get hasData => _currentFrame != null;
  String? get errorMessage => _errorMessage;
  DicomMetadata? get metadata => _currentFrame?.metadata;

  double? get windowCenter => _currentWindowCenter;
  double? get windowWidth => _currentWindowWidth;

  /// Loads and processes a DICOM file from the given [filePath].
  ///
  /// * [config]: Optional configuration to control how Rust processes the file
  ///   (e.g., skipping pixel data if you only need metadata).
  ///
  /// Throws a [DicomProcessingException] if the file is invalid or corrupted.
  Future<void> loadFromFile({
    required final String filePath,
    final DicomConfig? config,
  }) async {
    if (_isLoading) return;

    _setLoading(true);
    _clearError();

    try {
      final DicomConfig finalConfig = config ?? await DicomConfig.default_();

      // Call the Rust FFI layer (Runs in a background isolate automatically)
      _currentFrame = await loadDicom(path: filePath, config: finalConfig);

      // Initialize interactive windowing values from the file's metadata
      _currentWindowCenter = _currentFrame?.metadata.windowCenter;
      _currentWindowWidth = _currentFrame?.metadata.windowWidth;
    } catch (e) {
      _errorMessage = 'Failed to load DICOM: ${e.toString()}';
      throw DicomProcessingException(_errorMessage!);
    } finally {
      _setLoading(false);
    }
  }

  /// Adjusts the Window Center and Width (Brightness & Contrast).
  ///
  /// This is typically called continuously by a gesture detector in the UI.
  ///
  /// * [deltaX]: Changes the window width (contrast).
  /// * [deltaY]: Changes the window center (brightness).
  void adjustWindowing({
    required final double deltaX,
    required final double deltaY,
  }) {
    if (!hasData || _currentWindowCenter == null || _currentWindowWidth == null)
      return;

    // Adjust values (sensitivity can be tweaked)
    final sensitivity = 1.5;
    _currentWindowWidth = (_currentWindowWidth! + (deltaX * sensitivity)).clamp(
      1.0,
      8000.0,
    );
    _currentWindowCenter = _currentWindowCenter! + (deltaY * sensitivity);

    // Notify the widget to redraw using the new shader parameters
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
    _currentWindowCenter = null;
    _currentWindowWidth = null;
    _clearError();
    notifyListeners();
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
