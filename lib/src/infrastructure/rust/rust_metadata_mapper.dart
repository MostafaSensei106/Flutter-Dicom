import 'dart:typed_data';

import '../../domain/dicom_geometry.dart';
import '../../domain/dicom_metadata.dart';
import '../../domain/dicom_pixel_data.dart';
import '../../domain/dicom_tag_id.dart';
import '../../domain/dicom_windowing.dart';
import '../../rust/api/core/models/dicom_frame_result.dart' as rust;
import '../../rust/api/core/models/dicom_metadata.dart' as rust;

/// Maps FRB-generated structs onto domain contracts.
///
/// This is the only place that knows the generated shapes — the public API
/// never imports `src/rust/`.
abstract final class RustMetadataMapper {
  /// Converts generated metadata to the domain contract.
  static DicomMetadata toDomain(final rust.DicomMetadata m) {
    final spacing = _parseSpacing(m.pixelSpacing);
    final orientation = _parseOrientation(m.imageOrientationPatient);
    final position = _parsePosition(m.imagePositionPatient);
    final presets = m.windowWidth > 0
        ? [
            DicomWindow(
              center: m.windowCenter.toDouble(),
              width: m.windowWidth.toDouble(),
            ),
          ]
        : <DicomWindow>[];
    return DicomMetadata(
      patientName: _clean(m.patientName),
      patientId: _clean(m.patientId),
      modality:
          m.modality == 'Unknown' ? null : DicomModality.parse(m.modality),
      rows: m.height,
      columns: m.width,
      bitsAllocated: m.bitsAllocated,
      bitsStored: m.bitsStored,
      highBit: m.highBit,
      pixelRepresentation: DicomPixelRepresentation.fromRaw(
        m.pixelRepresentation,
      ),
      samplesPerPixel: m.samplesPerPixel,
      photometricInterpretation: DicomPhotometricInterpretation.parse(
        m.photometricInterpretation,
      ),
      numberOfFrames: m.numberOfFrames,
      pixelSpacing: spacing,
      imageOrientationPatient: orientation,
      imagePositionPatient: position,
      windowPresets: presets,
      extraTags: _extraTags(m),
    );
  }

  /// Converts a decoded frame buffer to the sealed pixel hierarchy.
  static DicomPixelData toPixels({
    required final rust.DicomFrameResult result,
    required final int frameIndex,
  }) {
    final m = result.metadata;
    final transform = DicomPixelTransform(
      rescaleSlope: m.rescaleSlope.toDouble(),
      rescaleIntercept: m.rescaleIntercept.toDouble(),
      representation: DicomPixelRepresentation.fromRaw(
        m.pixelRepresentation,
      ),
      bitsAllocated: m.bitsAllocated,
    );
    if (m.samplesPerPixel == 3) {
      final bytes = Uint8List(result.pixelData.length);
      for (var i = 0; i < result.pixelData.length; i++) {
        bytes[i] = result.pixelData[i].clamp(0, 255);
      }
      return DicomRgbPixelData(
        buffer: bytes,
        width: m.width,
        height: m.height,
        frameIndex: frameIndex,
        transform: transform,
      );
    }
    if (m.pixelRepresentation == 0 && m.bitsAllocated <= 8) {
      final bytes = Uint8List(result.pixelData.length);
      for (var i = 0; i < result.pixelData.length; i++) {
        bytes[i] = result.pixelData[i].clamp(0, 255);
      }
      return DicomUint8PixelData(
        buffer: bytes,
        width: m.width,
        height: m.height,
        frameIndex: frameIndex,
        transform: transform,
      );
    }
    return DicomInt16PixelData(
      buffer: result.pixelData,
      width: m.width,
      height: m.height,
      frameIndex: frameIndex,
      transform: transform,
    );
  }

  static String? _clean(final String value) {
    final v = value.trim();
    return v.isEmpty || v == 'Unknown' ? null : v;
  }

  static DicomPixelSpacing? _parseSpacing(final String raw) {
    final parts = raw.split('\\');
    if (parts.length < 2) return null;
    final row = double.tryParse(parts[0].trim());
    final col = double.tryParse(parts[1].trim());
    if (row == null || col == null || row <= 0 || col <= 0) return null;
    return DicomPixelSpacing(row, col);
  }

  static List<double>? _parseDoubles(final String raw, final int count) {
    final parts = raw.split('\\');
    if (parts.length < count) return null;
    final out = <double>[];
    for (final p in parts.take(count)) {
      final v = double.tryParse(p.trim());
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  static DicomOrientation? _parseOrientation(final String raw) {
    final v = _parseDoubles(raw, 6);
    if (v == null) return null;
    return DicomOrientation(
      rowCosines: v.sublist(0, 3),
      columnCosines: v.sublist(3, 6),
    );
  }

  /// Parses an Image Orientation Patient value for series sorting.
  static DicomOrientation? parseOrientation(final String raw) =>
      _parseOrientation(raw);

  static DicomPosition? _parsePosition(final String raw) {
    final v = _parseDoubles(raw, 3);
    if (v == null) return null;
    return DicomPosition(v[0], v[1], v[2]);
  }

  /// Parses an Image Position Patient value for series sorting.
  static DicomPosition? parsePosition(final String raw) =>
      _parsePosition(raw);

  /// Parses an Instance Number value for series sorting.
  static int? parseInstanceNumber(final String raw) {
    final v = int.tryParse(raw.trim());
    if (v != null) return v;
    return double.tryParse(raw.trim())?.toInt();
  }

  /// Stashes identity tags (UIDs, dates) that have no typed metadata slot.
  static Map<DicomTagId, Object?> _extraTags(final rust.DicomMetadata m) {
    final tags = <DicomTagId, Object?>{};
    final studyUid = m.studyInstanceUid.trim();
    if (studyUid.isNotEmpty && studyUid != 'Unknown') {
      tags[DicomTagId.studyInstanceUid] = studyUid;
    }
    final seriesUid = m.seriesInstanceUid.trim();
    if (seriesUid.isNotEmpty && seriesUid != 'Unknown') {
      tags[DicomTagId.seriesInstanceUid] = seriesUid;
    }
    final sopUid = m.sopInstanceUid.trim();
    if (sopUid.isNotEmpty && sopUid != 'Unknown') {
      tags[DicomTagId.sopInstanceUid] = sopUid;
    }
    final date = _parseDate(m.studyDate);
    if (date != null) tags[DicomTagId.studyDate] = date;
    return tags;
  }

  /// Parses a DICOM DA value (`YYYYMMDD`) for study dates.
  static DateTime? _parseDate(final String raw) {
    final v = raw.trim();
    if (v.length != 8) return null;
    final y = int.tryParse(v.substring(0, 4));
    final m = int.tryParse(v.substring(4, 6));
    final d = int.tryParse(v.substring(6, 8));
    if (y == null || m == null || d == null) return null;
    return DateTime.tryParse(
      '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-'
      '${d.toString().padLeft(2, '0')}',
    );
  }
}
