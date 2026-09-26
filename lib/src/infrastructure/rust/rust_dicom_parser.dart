import '../../application/ports/dicom_parser.dart';
import '../../domain/dicom_frame.dart';
import '../../domain/dicom_metadata.dart';
import '../../domain/dicom_pixel_data.dart';
import '../../domain/dicom_source.dart';
import '../../errors/dicom_exception.dart';
import '../../rust/api/core/config/dicom_config.dart';
import '../../rust/api/init.dart';
import 'rust_metadata_mapper.dart';

/// Metadata-only config reused for lazy parsing.
const _metaConfig = DicomConfig(
  autoNormalize: false,
  skipPixels: true,
  frameIndex: 0,
);

/// Rust-backed parser — metadata now, pixels on demand.
///
/// `parse` never decodes pixel buffers; the returned provider fetches each
/// frame through the FRB bridge only when `get(index)` is called.
final class RustDicomParser implements DicomParser {
  /// Creates a Rust-backed lazy parser.
  const RustDicomParser();

  @override
  Future<DicomParseResult> parse(
    final DicomSource source, {
    final DicomParseOptions options = const DicomParseOptions(),
  }) async {
    try {
      return await _parseInner(source);
    } catch (e) {
      throw DicomProcessingException('Failed to parse DICOM source', e);
    }
  }

  Future<DicomParseResult> _parseInner(final DicomSource source) async {
    switch (source) {
      case DicomFileSource(:final path):
        final result = await loadDicom(path: path, config: _metaConfig);
        final meta = RustMetadataMapper.toDomain(result.metadata);
        return DicomParseResult(
          metadata: meta,
          frames: _RustFrameProvider(source: source, metadata: meta),
        );
      case DicomBytesSource(:final bytes):
        final result = await loadDicomFromBytes(
          bytes: bytes,
          config: _metaConfig,
        );
        final meta = RustMetadataMapper.toDomain(result.metadata);
        return DicomParseResult(
          metadata: meta,
          frames: _RustFrameProvider(source: source, metadata: meta),
        );
      case DicomFilesSource(:final paths):
        if (paths.isEmpty) {
          throw const DicomConfigurationException('Empty file list');
        }
        final result = await loadDicom(
          path: paths.first,
          config: _metaConfig,
        );
        final meta = _asFileList(
          RustMetadataMapper.toDomain(result.metadata),
          paths.length,
        );
        return DicomParseResult(
          metadata: meta,
          frames: _RustFrameProvider(source: source, metadata: meta),
        );
      case DicomBytesListSource(:final files):
        if (files.isEmpty) {
          throw const DicomConfigurationException('Empty bytes list');
        }
        final result = await loadDicomFromBytes(
          bytes: files.first,
          config: _metaConfig,
        );
        final meta = _asFileList(
          RustMetadataMapper.toDomain(result.metadata),
          files.length,
        );
        return DicomParseResult(
          metadata: meta,
          frames: _RustFrameProvider(source: source, metadata: meta),
        );
    }
  }

  /// A file list behaves as one multi-frame dataset.
  DicomMetadata _asFileList(final DicomMetadata first, final int count) {
    return DicomMetadata(
      patientName: first.patientName,
      patientId: first.patientId,
      patientSex: first.patientSex,
      modality: first.modality,
      rows: first.rows,
      columns: first.columns,
      bitsAllocated: first.bitsAllocated,
      bitsStored: first.bitsStored,
      highBit: first.highBit,
      pixelRepresentation: first.pixelRepresentation,
      samplesPerPixel: first.samplesPerPixel,
      photometricInterpretation: first.photometricInterpretation,
      numberOfFrames: count,
      pixelSpacing: first.pixelSpacing,
      imagerPixelSpacing: first.imagerPixelSpacing,
      imageOrientationPatient: first.imageOrientationPatient,
      imagePositionPatient: first.imagePositionPatient,
      windowPresets: first.windowPresets,
      transferSyntax: first.transferSyntax,
      extraTags: first.extraTags,
    );
  }
}

/// Lazy provider decoding one frame per `get` call.
final class _RustFrameProvider implements DicomFrameProvider {
  _RustFrameProvider({required this.source, required this.metadata});

  final DicomSource source;
  final DicomMetadata metadata;

  @override
  int get frameCount => metadata.numberOfFrames;

  @override
  Future<DicomFrame> get(final int index) async {
    if (index < 0 || index >= frameCount) {
      throw DicomConfigurationException('Frame $index out of range');
    }
    final pixels = await fetchPixels(source, index);
    return DicomFrame(index: index, metadata: metadata, pixelData: pixels);
  }

  /// Shared fetch used by the provider (and tests).
  static Future<DicomPixelData> fetchPixels(
    final DicomSource source,
    final int index,
  ) async {
    try {
      switch (source) {
        case DicomFileSource(:final path):
          final result = await loadDicom(
            path: path,
            config: DicomConfig(
              autoNormalize: false,
              skipPixels: false,
              frameIndex: index,
            ),
          );
          return RustMetadataMapper.toPixels(
            result: result,
            frameIndex: index,
          );
        case DicomBytesSource(:final bytes):
          final result = await loadDicomFromBytes(
            bytes: bytes,
            config: DicomConfig(
              autoNormalize: false,
              skipPixels: false,
              frameIndex: index,
            ),
          );
          return RustMetadataMapper.toPixels(
            result: result,
            frameIndex: index,
          );
        case DicomFilesSource(:final paths):
          final result = await loadDicom(
            path: paths[index],
            config: const DicomConfig(
              autoNormalize: false,
              skipPixels: false,
              frameIndex: 0,
            ),
          );
          return RustMetadataMapper.toPixels(
            result: result,
            frameIndex: index,
          );
        case DicomBytesListSource(:final files):
          final result = await loadDicomFromBytes(
            bytes: files[index],
            config: const DicomConfig(
              autoNormalize: false,
              skipPixels: false,
              frameIndex: 0,
            ),
          );
          return RustMetadataMapper.toPixels(
            result: result,
            frameIndex: index,
          );
      }
    } catch (e) {
      throw DicomProcessingException('Failed to decode frame $index', e);
    }
  }
}
