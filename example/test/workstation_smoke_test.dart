import 'package:flutter_dicom/flutter_dicom.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_dicom_example/main.dart';

class _FakeParser implements DicomParser {
  @override
  Future<DicomParseResult> parse(
    final DicomSource source, {
    final DicomParseOptions options = const DicomParseOptions(),
  }) =>
      throw UnimplementedError();
}

class _FakeEngine implements DicomEngine {
  @override
  DicomParser get parser => _FakeParser();

  @override
  DicomDecoder get decoder => throw UnimplementedError();

  @override
  DicomRenderer get renderer => throw UnimplementedError();

  @override
  DicomExporter get exporter => const MultiFormatDicomExporter();

  @override
  DicomSeriesLoader get seriesLoader => throw UnimplementedError();

  @override
  Future<DicomDocument> open(
    final DicomSource source, {
    final DicomOpenOptions options = const DicomOpenOptions(),
  }) =>
      throw UnimplementedError();

  @override
  Future<DicomSeries> openSeries(
    final DicomSource source, {
    final DicomSeriesLoadOptions options = const DicomSeriesLoadOptions(),
  }) =>
      throw UnimplementedError();

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('workstation builds all four tabs', (final tester) async {
    await tester.pumpWidget(MyApp(engineOverride: _FakeEngine()));
    // AppBar + bottom nav render without a loaded document.
    expect(find.text('DICOM Workstation'), findsOneWidget);
    expect(find.text('Viewer'), findsOneWidget);
    expect(find.text('Measure'), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);

    // Empty viewer state (no document loaded yet).
    expect(find.text('No DICOM data loaded.'), findsOneWidget);

    // Measure tab empty state.
    await tester.tap(find.text('Measure'));
    await tester.pumpAndSettle();
    expect(
      find.text('Load an image in the Viewer tab.'),
      findsOneWidget,
    );

    // Volume tab assemble prompt.
    await tester.tap(find.text('Volume'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Assemble volume'), findsOneWidget);

    // Share tab sections.
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Image export'), findsOneWidget);
    expect(find.textContaining('DICOM writing'), findsOneWidget);
    expect(find.textContaining('DICOMweb'), findsOneWidget);
    expect(find.textContaining('DIMSE'), findsOneWidget);
    expect(find.byType(DicomViewer), findsNothing);
  });
}
