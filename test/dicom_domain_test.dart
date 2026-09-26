import 'dart:typed_data';

import 'package:flutter_dicom/flutter_dicom.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DicomWindow', () {
    test('linear map clamps to [0, 1]', () {
      const window = DicomWindow(center: 40, width: 400);
      expect(window.apply(-1000), 0.0);
      expect(window.apply(40), closeTo(0.5, 1e-9));
      expect(window.apply(1000), 1.0);
      expect(window.min, -160.0);
      expect(window.max, 240.0);
    });

    test('copyWith clamps width', () {
      const window = DicomWindow(center: 0, width: 100);
      expect(window.copyWith(width: -5).width, 1.0);
      expect(window.copyWith(width: 99999).width, 8000.0);
    });

    test('presets are sane', () {
      expect(DicomWindowPreset.bone.center, 400);
      expect(DicomWindowPreset.lung.center, -600);
      expect(DicomWindowPreset.all.length, 5);
    });
  });

  group('DicomPhotometricInterpretation', () {
    test('parses and flags inversion', () {
      expect(
        DicomPhotometricInterpretation.parse('MONOCHROME1').isInverted,
        isTrue,
      );
      expect(
        DicomPhotometricInterpretation.parse('MONOCHROME2').isInverted,
        isFalse,
      );
      expect(
        DicomPhotometricInterpretation.parse('RGB'),
        DicomPhotometricInterpretation.rgb,
      );
      expect(
        DicomPhotometricInterpretation.parse('nope'),
        DicomPhotometricInterpretation.unknown,
      );
    });
  });

  group('DicomPixelSpacing', () {
    test('parses DICOM format', () {
      final spacing = DicomPixelSpacing.tryParse(r'0.5\0.5');
      expect(spacing?.row, 0.5);
      expect(spacing?.column, 0.5);
    });

    test('rejects garbage', () {
      expect(DicomPixelSpacing.tryParse(''), isNull);
      expect(DicomPixelSpacing.tryParse(r'0\-1'), isNull);
      expect(DicomPixelSpacing.tryParse('abc'), isNull);
    });
  });

  group('LruFrameCache', () {
    test('evicts least-recently-used', () {
      final cache = LruFrameCache<String>(capacity: 2);
      cache.put(0, 'a');
      cache.put(1, 'b');
      expect(cache.get(0), 'a'); // 0 is now MRU
      cache.put(2, 'c'); // evicts 1
      expect(cache.get(1), isNull);
      expect(cache.get(0), 'a');
      expect(cache.get(2), 'c');
    });
  });

  group('Viewer commands', () {
    test('SetWindow / ToggleInvert / SetFrame compose', () {
      const state = DicomViewerState();
      final windowed = const SetWindowCommand(
        center: 400,
        width: 1800,
      ).execute(state);
      expect(windowed.window.center, 400);
      expect(windowed.window.width, 1800);

      final inverted = const ToggleInvertCommand().execute(windowed);
      expect(inverted.invert, isTrue);

      final framed = const SetFrameCommand(3).execute(inverted);
      expect(framed.currentFrame, 3);
      // Original untouched (immutability).
      expect(state.window.center, 40);
      expect(state.invert, isFalse);
    });
  });

  group('DicomSource', () {
    test('factory hierarchy constructs', () {
      expect(const DicomSource.file('a.dcm'), isA<DicomSource>());
      expect(
        DicomSource.bytes(Uint8List.fromList([1, 2])),
        isA<DicomSource>(),
      );
      expect(const DicomSource.files(['a']), isA<DicomSource>());
      expect(
        DicomSource.bytesList([Uint8List.fromList([1])]),
        isA<DicomSource>(),
      );
    });
  });

  group('DicomPixelTransform', () {
    test('maps stored values to modality values', () {
      const signed = DicomPixelTransform(
        rescaleSlope: 1,
        rescaleIntercept: -1024,
        representation: DicomPixelRepresentation.signed,
      );
      expect(signed.toModalityValue(100), -924.0);

      const unsigned = DicomPixelTransform(
        rescaleSlope: 1,
        rescaleIntercept: -1024,
        representation: DicomPixelRepresentation.unsigned,
        bitsAllocated: 16,
      );
      expect(unsigned.toModalityValue(-32768), -1024.0);
      expect(unsigned.toModalityValue(0), 31744.0);
    });
  });

  group('DicomPixelData variants', () {
    test('int16 modality mapping', () {
      final pixels = DicomInt16PixelData(
        buffer: Int16List.fromList([0, 100]),
        width: 2,
        height: 1,
        transform: const DicomPixelTransform(
          rescaleSlope: 1,
          rescaleIntercept: -1024,
          representation: DicomPixelRepresentation.signed,
        ),
      );
      expect(pixels.format, DicomPixelFormat.int16);
      expect(pixels.length, 2);
      expect(pixels.modalityAt(1), -924.0);
    });
  });

  group('DicomMetadata contract', () {
    test('default window falls back to presets', () {
      const meta = DicomMetadata(
        rows: 512,
        columns: 512,
        bitsAllocated: 16,
        bitsStored: 16,
        highBit: 15,
        pixelRepresentation: DicomPixelRepresentation.unsigned,
        samplesPerPixel: 1,
        photometricInterpretation:
            DicomPhotometricInterpretation.monochrome2,
        numberOfFrames: 1,
      );
      expect(meta.defaultWindow.center, 40);
      expect(meta.width, 512);
      expect(meta.tag<String>(DicomTagId.patientName), isNull);
    });

    test('tag ids format', () {
      expect(DicomTagId.rows.toString(), '(0028,0010)');
    });
  });

  group('DicomGeometry', () {
    test('screen-to-image mapping', () {
      const geometry = DicomGeometry(imageWidth: 512, imageHeight: 512);
      final point = geometry.screenToImage(
        const DicomPoint(256, 128),
        const DicomViewport(width: 512, height: 512),
      );
      expect(point?.x, 256);
      expect(point?.y, 128);
    });

    test('pixels-to-mm without spacing is null', () {
      const geometry = DicomGeometry(imageWidth: 512, imageHeight: 512);
      expect(geometry.pixelsToMillimeters(10), isNull);
      const spaced = DicomGeometry(
        imageWidth: 512,
        imageHeight: 512,
        pixelSpacing: DicomPixelSpacing(0.5, 0.5),
      );
      expect(spaced.pixelsToMillimeters(10), 5.0);
    });
  });

  group('Probe / ROI / Ruler', () {
    DicomInt16PixelData pixels() => DicomInt16PixelData(
      buffer: Int16List.fromList(List.filled(16, 100)),
      width: 4,
      height: 4,
      transform: const DicomPixelTransform(
        rescaleSlope: 1,
        rescaleIntercept: -1024,
        representation: DicomPixelRepresentation.signed,
      ),
    );

    test('probe reports modality values', () {
      const probe = ModalityProbe();
      final result = probe.probe(pixels(), const DicomPoint(1, 1));
      expect(result.rawValue, 100.0);
      expect(result.hu, -924.0);
    });

    test('roi statistics', () async {
      const roi = DicomRoi(DicomRect(0, 0, 4, 4));
      final stats = await roi.analyze(pixels());
      expect(stats.pixelCount, 16);
      expect(stats.mean, -924.0);
      expect(stats.min, -924.0);
      expect(stats.max, -924.0);
    });

    test('ruler measures in px and mm', () {
      const ruler = DicomRuler();
      const geometry = DicomGeometry(
        imageWidth: 4,
        imageHeight: 4,
        pixelSpacing: DicomPixelSpacing(0.5, 0.5),
      );
      final m = ruler.measure(
        const DicomPoint(0, 0),
        const DicomPoint(3, 4),
        geometry,
      );
      expect(m.pixelDistance, 5.0);
      expect(m.millimeters, 2.5);
    });
  });

  group('Annotations', () {
    test('sealed hierarchy constructs', () {
      const line = LineAnnotation(
        id: 'a',
        start: DicomPoint(0, 0),
        end: DicomPoint(1, 1),
      );
      expect(line, isA<DicomAnnotation>());
    });
  });
}
