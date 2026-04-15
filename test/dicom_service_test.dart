import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_dicom/flutter_dicom.dart';

class MockDicomLoader extends Mock implements IDicomLoader {}

void main() {
  late DicomService service;
  late MockDicomLoader mockLoader;

  setUp(() {
    mockLoader = MockDicomLoader();
    service = DicomService(loader: mockLoader);
  });

  group('DicomService', () {
    const testPath = '/path/to/dicom.dcm';
    const testMetadata = DicomMetadata(
      width: 512,
      height: 512,
      windowCenter: 40.0,
      windowWidth: 400.0,
      rescaleIntercept: -1024.0,
      rescaleSlope: 1.0,
      patientName: 'John Doe',
      photometricInterpretation: 'MONOCHROME2',
      samplesPerPixel: 1,
      bitsAllocated: 16,
      bitsStored: 12,
      highBit: 11,
      pixelRepresentation: 0,
    );

    test('loadFrame calls loader with correct parameters', () async {
      final mockResult = DicomFrameResult(
        metadata: testMetadata,
        pixelData: Int16List(0),
      );

      when(() => mockLoader.load(testPath, config: any(named: 'config')))
          .thenAnswer((_) async => mockResult);

      final result = await service.loadFrame(testPath);

      expect(result, mockResult);
      verify(() => mockLoader.load(testPath, config: any(named: 'config')))
          .called(1);
    });

    test('loadFrame propagates errors from loader', () async {
      when(() => mockLoader.load(testPath, config: any(named: 'config')))
          .thenThrow(Exception('Load failed'));

      expect(() => service.loadFrame(testPath), throwsException);
    });
  });
}
