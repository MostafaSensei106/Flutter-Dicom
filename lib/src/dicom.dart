import '../flutter_dicom.dart';

/// Core entrypoint for the Flutter Dicom plugin.
abstract class FlutterDicom {
  /// Initializes the Rust bindings and underlying WASM/FFI bridges.
  /// Must be called before using any DICOM functionality.
  static Future<void> init() async {
    await RustLib.init();
  }
}
