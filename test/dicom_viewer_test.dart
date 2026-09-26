import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_dicom/flutter_dicom.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeParser implements DicomParser {
  FakeParser({this.fail = false});

  final bool fail;

  static const meta = DicomMetadata(
    rows: 4,
    columns: 4,
    bitsAllocated: 16,
    bitsStored: 16,
    highBit: 15,
    pixelRepresentation: DicomPixelRepresentation.unsigned,
    samplesPerPixel: 1,
    photometricInterpretation: DicomPhotometricInterpretation.monochrome2,
    numberOfFrames: 2,
    pixelSpacing: DicomPixelSpacing(0.5, 0.5),
  );

  @override
  Future<DicomParseResult> parse(
    DicomSource source, {
    DicomParseOptions options = const DicomParseOptions(),
  }) async {
    if (fail) throw const DicomProcessingException('parse failed');
    return DicomParseResult(metadata: meta, frames: _FakeProvider());
  }
}

class _FakeProvider implements DicomFrameProvider {
  @override
  int get frameCount => 2;

  @override
  Future<DicomFrame> get(int index) async => DicomFrame(
        index: index,
        metadata: FakeParser.meta,
        pixelData: DicomInt16PixelData(
          buffer: Int16List(16),
          width: 4,
          height: 4,
        ),
      );
}

void main() {
  group('DicomViewer', () {
    testWidgets('renders loading then image', (tester) async {
      final controller = DefaultDicomViewerController(parser: FakeParser());
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DicomViewer(controller: controller))),
      );
      expect(find.text('No DICOM data loaded.'), findsOneWidget);

      await tester
          .runAsync(() => controller.load(const DicomSource.file('fake.dcm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller.state.status, isA<DicomViewerReady>());
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('shows error view on failure', (tester) async {
      final controller = DefaultDicomViewerController(
        parser: FakeParser(fail: true),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DicomViewer(controller: controller))),
      );
      await tester.runAsync(() async {
        try {
          await controller.load(const DicomSource.file('fake.dcm'));
        } catch (_) {}
      });
      await tester.pump();

      expect(controller.state.status, isA<DicomViewerError>());
      expect(find.textContaining('parse failed'), findsOneWidget);
    });

    testWidgets('custom builders override defaults', (tester) async {
      final controller = DefaultDicomViewerController(
        parser: FakeParser(fail: true),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DicomViewer(
              controller: controller,
              errorBuilder: (context, error) => const Text('custom error view'),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        try {
          await controller.load(const DicomSource.file('fake.dcm'));
        } catch (_) {}
      });
      await tester.pump();

      expect(find.text('custom error view'), findsOneWidget);
    });

    test('controller windowing commands update state', () async {
      final controller = DefaultDicomViewerController(parser: FakeParser());
      addTearDown(controller.dispose);

      await controller.load(const DicomSource.file('fake.dcm'));
      controller.setWindow(DicomWindowPreset.bone);
      expect(controller.state.window.center, 400);

      controller.setInvert(true);
      expect(controller.state.invert, isTrue);

      await controller.setFrame(1);
      expect(controller.state.currentFrame, 1);

      controller.reset();
      expect(controller.state.invert, isFalse);
    });
  });
}
