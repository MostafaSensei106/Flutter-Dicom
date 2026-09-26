import 'dart:async';

import 'application/ports/dicom_decoder.dart';
import 'application/ports/dicom_exporter.dart';
import 'application/ports/dicom_parser.dart';
import 'application/ports/dicom_renderer.dart';
import 'domain/dicom_frame.dart';
import 'domain/dicom_metadata.dart';
import 'domain/dicom_pixel_data.dart';
import 'domain/dicom_source.dart';
import 'export/dicom_export.dart';
import 'infrastructure/rust/rust_dicom_decoder.dart';
import 'infrastructure/rust/rust_dicom_parser.dart';
import 'rust/frb_generated.dart';

/// Engine configuration (dependency injection root).
final class DicomEngineConfig {
  const DicomEngineConfig();
}

/// Open tuning.
final class DicomOpenOptions {
  const DicomOpenOptions({
    this.parseOptions = const DicomParseOptions(),
    this.decodeOptions = const DicomDecodeOptions(),
  });

  final DicomParseOptions parseOptions;
  final DicomDecodeOptions decodeOptions;
}

/// Opened document — metadata now, pixels on demand.
final class DicomDocument {
  const DicomDocument({required this.metadata, required this.frames});

  final DicomMetadata metadata;
  final DicomFrameProvider frames;

  int get frameCount => frames.frameCount;
}

/// Runtime facade — orchestration only, never a God Object.
///
/// ```dart
/// final engine = await DicomEngine.create();
/// final doc = await engine.open(const DicomSource.file('scan.dcm'));
/// ```
///
/// `create` initializes the native bridge, so callers never touch `RustLib`.
abstract interface class DicomEngine {
  DicomParser get parser;
  DicomDecoder get decoder;
  DicomRenderer get renderer;
  DicomExporter get exporter;

  Future<DicomDocument> open(
    DicomSource source, {
    DicomOpenOptions options = const DicomOpenOptions(),
  });

  Future<void> dispose();

  static Future<DicomEngine> create({
    DicomEngineConfig config = const DicomEngineConfig(),
  }) async {
    await _Bridge.ensureInitialized();
    return const _DefaultDicomEngine();
  }
}

/// One-time native bridge initialization (FRB forbids double init).
abstract final class _Bridge {
  static bool _ready = false;

  static Future<void> ensureInitialized() async {
    if (_ready) return;
    await RustLib.init();
    _ready = true;
  }
}

/// Default engine wiring Rust-backed adapters behind the ports.
final class _DefaultDicomEngine implements DicomEngine {
  const _DefaultDicomEngine();

  @override
  DicomParser get parser => const RustDicomParser();

  @override
  DicomDecoder get decoder => const RustDicomDecoder();

  @override
  DicomRenderer get renderer => const _ViewerOwnedRenderer();

  @override
  DicomExporter get exporter => const PngDicomExporter();

  @override
  Future<DicomDocument> open(
    DicomSource source, {
    DicomOpenOptions options = const DicomOpenOptions(),
  }) async {
    final result = await parser.parse(source, options: options.parseOptions);
    return DicomDocument(metadata: result.metadata, frames: result.frames);
  }

  @override
  Future<void> dispose() async {}
}

/// GPU rendering stays owned by the viewer pipeline
/// (`DefaultDicomViewerController` + fragment shader); a standalone
/// off-screen renderer lands with the Phase 2 backend abstraction.
final class _ViewerOwnedRenderer implements DicomRenderer {
  const _ViewerOwnedRenderer();

  @override
  Future<DicomRenderResult> render(
    DicomPixelData pixels, {
    DicomRenderOptions options = const DicomRenderOptions(),
  }) =>
      throw UnimplementedError(
        'Off-screen rendering is not implemented; '
        'render through DicomViewer + DicomViewerController.',
      );
}
