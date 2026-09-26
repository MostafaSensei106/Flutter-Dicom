import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/dicom_source.dart';
import '../errors/dicom_exception.dart';
import '../series/dicom_series.dart';
import 'dicom_network.dart';

/// HTTP DICOMweb client: QIDO-RS search, WADO-RS retrieve, STOW-RS store.
///
/// `[baseUrl]` is the service root, e.g.
/// `http://pacs:8080/dicom-web`. The [HttpClient] is injected for tests;
/// defaults to a shared client. Application code never sees HTTP.
final class HttpDicomWebClient implements DicomWebClient {
  /// Creates a client over [baseUrl] with an optional [http] backend.
  HttpDicomWebClient({required this.baseUrl, final HttpClient? http})
      : _http = http ?? HttpClient();

  /// DICOMweb service root.
  final Uri baseUrl;

  /// Series loader used by [retrieveSeries] after temp-file staging.
  ///
  /// Must be set before calling [retrieveSeries]; search/retrieve/store
  /// work without it.
  DicomSeriesLoader? seriesLoader;

  final HttpClient _http;

  @override
  Future<List<DicomStudy>> searchStudies(
    final DicomStudyQuery query,
  ) async {
    final params = <String, String>{
      if (query.patientName != null) 'PatientName': query.patientName!,
      if (query.studyDate != null) 'StudyDate': query.studyDate!,
      if (query.modality != null) 'ModalitiesInStudy': query.modality!,
    };
    final uri = baseUrl.replace(
      path: '${baseUrl.path}/studies',
      queryParameters: params.isEmpty ? null : params,
    );
    final request = await _http.getUrl(uri);
    request.headers.set('Accept', 'application/dicom+json');
    final response = await request.close();
    _check(response, 'QIDO-RS search');
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as List;
    return [
      for (final entry in json)
        if (entry is Map<String, dynamic>) _studyFromJson(entry),
    ];
  }

  @override
  Future<DicomSeries> retrieveSeries(
    final String studyUid,
    final String seriesUid,
  ) async {
    final loader = seriesLoader;
    if (loader == null) {
      throw const DicomConfigurationException(
        'retrieveSeries needs a seriesLoader (set HttpDicomWebClient.seriesLoader)',
      );
    }
    // Series metadata lists instance UIDs; instances stage as temp files so
    // the shared file-based series loader applies (spatial sorting included).
    final metaUri = baseUrl.replace(
      path: '${baseUrl.path}/studies/$studyUid/series/$seriesUid/metadata',
    );
    final metaRequest = await _http.getUrl(metaUri);
    metaRequest.headers.set('Accept', 'application/dicom+json');
    final metaResponse = await metaRequest.close();
    _check(metaResponse, 'WADO-RS series metadata');
    final metaBody = await metaResponse.transform(utf8.decoder).join();
    final meta = jsonDecode(metaBody) as List;
    final instanceUids = <String>[
      for (final entry in meta)
        if (entry is Map<String, dynamic>)
          _firstString(entry, '00080018'),
    ].where((final uid) => uid.isNotEmpty).toList();
    if (instanceUids.isEmpty) {
      throw const DicomProcessingException('Series has no instances');
    }
    final dir = await Directory.systemTemp.createTemp('dicomweb_series_');
    final paths = <String>[];
    for (var i = 0; i < instanceUids.length; i++) {
      final bytes = await retrieveInstance(
        studyUid,
        seriesUid,
        instanceUids[i],
      );
      final path = '${dir.path}/instance_$i.dcm';
      await File(path).writeAsBytes(bytes);
      paths.add(path);
    }
    return loader.load(DicomSource.files(paths));
  }

  @override
  Future<Uint8List> retrieveInstance(
    final String studyUid,
    final String seriesUid,
    final String instanceUid,
  ) async {
    final uri = baseUrl.replace(
      path: '${baseUrl.path}/studies/$studyUid/series/$seriesUid'
          '/instances/$instanceUid',
    );
    final request = await _http.getUrl(uri);
    request.headers.set('Accept', 'application/dicom; transfer-syntax=*');
    final response = await request.close();
    _check(response, 'WADO-RS retrieve');
    final chunks = <int>[];
    await for (final chunk in response) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  @override
  Future<void> storeInstance(final Uint8List dicomBytes) async {
    final boundary =
        'dicomweb_${DateTime.now().microsecondsSinceEpoch}';
    final uri = baseUrl.replace(path: '${baseUrl.path}/studies');
    final request = await _http.postUrl(uri);
    request.headers.set(
      'Content-Type',
      'multipart/related; type="application/dicom"; boundary=$boundary',
    );
    final out = BytesBuilder();
    void line(final String s) => out.add(utf8.encode('$s\r\n'));
    line('--$boundary');
    line('Content-Type: application/dicom');
    line('');
    out.add(dicomBytes);
    line('');
    line('--$boundary--');
    request.add(out.toBytes());
    final response = await request.close();
    await response.drain();
    _check(response, 'STOW-RS store');
  }

  void _check(final HttpClientResponse response, final String op) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw DicomNetworkException(
      '$op failed with HTTP ${response.statusCode}',
    );
  }

  DicomStudy _studyFromJson(final Map<String, dynamic> entry) {
    return DicomStudy(
      studyUid: _firstString(entry, '0020000D'),
      patientName: _patientName(entry),
    );
  }

  String _firstString(final Map<String, dynamic> entry, final String tag) {
    final attr = entry[tag];
    if (attr is! Map<String, dynamic>) return '';
    final values = attr['Value'];
    if (values is! List || values.isEmpty) return '';
    return '${values.first}'.trim();
  }

  String? _patientName(final Map<String, dynamic> entry) {
    final attr = entry['00100010'];
    if (attr is! Map<String, dynamic>) return null;
    final values = attr['Value'];
    if (values is! List || values.isEmpty) return null;
    final first = values.first;
    if (first is Map<String, dynamic>) {
      final alpha = first['Alphabetic'];
      if (alpha is String && alpha.trim().isNotEmpty) {
        return alpha.trim();
      }
      return '$first'.trim();
    }
    final s = '$first'.trim();
    return s.isEmpty ? null : s;
  }
}
