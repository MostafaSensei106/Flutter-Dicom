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
  /// Creates the engine configuration.
  const DicomEngineConfig();
}

/// Open tuning.
final class DicomOpenOptions {
  /// Creates open tuning with parse and decode options.
  const DicomOpenOptions({
    this.parseOptions = const DicomParseOptions(),
    this.decodeOptions = const DicomDecodeOptions(),
  });

  /// Options forwarded to the parser.
  final DicomParseOptions parseOptions;

  /// Options forwarded to the decoder.
  final DicomDecodeOptions decodeOptions;
}

/// Opened document — metadata now, pixels on demand.
final class DicomDocument {
  /// Creates an opened document with [metadata] and [frames].
  const DicomDocument({required this.metadata, required this.frames});

  /// Dataset metadata.
  final DicomMetadata metadata;

  /// Lazy provider for per-frame pixel data.
  final DicomFrameProvider frames;

  /// Total number of frames in the document.
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
  /// Parser used to open DICOM sources.
  DicomParser get parser;

  /// Decoder used for frame pixel data.
  DicomDecoder get decoder;

  /// Renderer used for off-screen rendering.
  DicomRenderer get renderer;

  /// Exporter used for encoded output.
  DicomExporter get exporter;

  /// Opens [source] into a lazily decoded document.
  Future<DicomDocument> open(
    final DicomSource source, {
    final DicomOpenOptions options = const DicomOpenOptions(),
  });

  /// Releases engine resources.
  Future<void> dispose();

  /// Creates a Rust-backed engine, initializing the native bridge once.
  static Future<DicomEngine> create({
    final DicomEngineConfig config = const DicomEngineConfig(),
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
    final DicomSource source, {
    final DicomOpenOptions options = const DicomOpenOptions(),
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
    final DicomPixelData pixels, {
    final DicomRenderOptions options = const DicomRenderOptions(),
  }) =>
      throw UnimplementedError(
        'Off-screen rendering is not implemented; '
        'render through DicomViewer + DicomViewerController.',
      );
}
