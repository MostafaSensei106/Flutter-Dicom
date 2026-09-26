// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:flutter_dicom/flutter_dicom.dart';
import 'package:flutter_test/flutter_test.dart';

// ============================================================
// DICOM Engine Benchmark Suite (new public API).
// Tests every phase: parse → decode → windowing → reset → dispose
// Covers: throughput, latency, stress, scrubbing, and edge cases
// ============================================================

void main() async {
  await DicomEngine.create();

  const seriesPath = 'test/series-00001';

  /// Returns sorted .dcm files from [path], fails if missing.
  Future<List<FileSystemEntity>> loadSeries(
    final String path, {
    final bool failIfMissing = true,
  }) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      if (failIfMissing) {
        fail(
          'Series directory not found at $path. '
          'Please ensure test data is present.',
        );
      }
      return [];
    }
    final files = directory
        .listSync()
        .where((final e) => e.path.endsWith('.dcm'))
        .toList()
      ..sort((final a, final b) => a.path.compareTo(b.path));
    return files;
  }

  /// Prints a separator line.
  void separator([final String char = '─', final int len = 52]) =>
      print(char * len);

  /// Formats milliseconds as a human-readable string.
  String fmtMs(final num ms) {
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(2)} s';
    return '${ms.toStringAsFixed(2)} ms';
  }

  // ──────────────────────────────────────────────────────────
  // GROUP 1 ▸ Throughput Benchmark
  // ──────────────────────────────────────────────────────────
  group('1 ▸ Throughput Benchmark (engine parse + decode)', () {
    test('High-throughput sequential decode', () async {
      final files = await loadSeries(seriesPath);
      final engine = await DicomEngine.create();

      print('');
      print('▶ THROUGHPUT — parse + first-frame decode × ${files.length}');
      separator();

      final latencies = <int>[];
      final sw = Stopwatch()..start();
      var errors = 0;
      for (final file in files) {
        final frameSw = Stopwatch()..start();
        try {
          final doc = await engine.open(DicomSource.file(file.path));
          await doc.frames.get(0);
        } catch (_) {
          errors++;
        }
        frameSw.stop();
        latencies.add(frameSw.elapsedMicroseconds);
      }
      sw.stop();

      latencies.sort();
      final avgUs = latencies.reduce((a, b) => a + b) / latencies.length;
      final p99 = latencies[(latencies.length * 0.99).floor()];
      final fps = files.length / (sw.elapsedMicroseconds / 1e6);
      print(
        '${fps.toStringAsFixed(1)} FPS │ avg ${fmtMs(avgUs / 1000)} │ '
        'p99 ${fmtMs(p99 / 1000)} │ errors $errors',
      );
      separator();
      expect(errors, 0);
      await engine.dispose();
    });
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 2 ▸ Latency Distribution
  // ──────────────────────────────────────────────────────────
  group('2 ▸ Per-Frame Latency Distribution', () {
    test('Latency percentiles (p50 / p95 / p99 / max)', () async {
      final files = await loadSeries(seriesPath);
      final engine = await DicomEngine.create();
      final samples = <int>[];

      for (var r = 0; r < 3; r++) {
        for (final file in files) {
          final sw = Stopwatch()..start();
          final doc = await engine.open(DicomSource.file(file.path));
          await doc.frames.get(0);
          sw.stop();
          samples.add(sw.elapsedMicroseconds);
        }
      }
      samples.sort();
      double pct(double p) =>
          samples[(samples.length * p).floor().clamp(0, samples.length - 1)] /
          1000;
      print('');
      print('▶ LATENCY DISTRIBUTION (${samples.length} samples)');
      separator();
      print('  p50 ${fmtMs(pct(0.5))} │ p95 ${fmtMs(pct(0.95))} │ '
          'p99 ${fmtMs(pct(0.99))} │ max ${fmtMs(samples.last / 1000)}');
      separator();
      expect(pct(0.99), lessThan(16.6 * 10)); // generous CI budget
      await engine.dispose();
    });
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 3 ▸ Windowing Stress
  // ──────────────────────────────────────────────────────────
  group('3 ▸ Windowing & Contrast Stress Test', () {
    test('Rapid setWindow ops stay real-time', () async {
      final files = await loadSeries(seriesPath);
      final controller = DefaultDicomViewerController();
      addTearDown(controller.dispose);
      await controller.load(DicomSource.file(files.first.path));

      const ops = 5000;
      final sw = Stopwatch()..start();
      for (var i = 0; i < ops; i++) {
        controller.setWindow(
          DicomWindow(center: 40 + (i % 400), width: 400 + (i % 800)),
        );
      }
      sw.stop();
      final perSec = ops / (sw.elapsedMicroseconds / 1e6);
      print('');
      print('▶ WINDOWING — $ops ops in ${fmtMs(sw.elapsedMilliseconds)} '
          '(${perSec.toStringAsFixed(0)} ops/s)');
      separator();
      expect(perSec, greaterThan(1000));
    });
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 4 ▸ Full Pipeline per File
  // ──────────────────────────────────────────────────────────
  group('4 ▸ Full Pipeline per File', () {
    test('load → window ×5 → reset → next', () async {
      final files = await loadSeries(seriesPath);
      final controller = DefaultDicomViewerController();
      addTearDown(controller.dispose);

      final sw = Stopwatch()..start();
      for (final file in files) {
        await controller.load(DicomSource.file(file.path));
        for (var i = 0; i < 5; i++) {
          controller.setWindow(DicomWindowPreset.bone);
          controller.setWindow(DicomWindowPreset.lung);
        }
        controller.reset();
      }
      sw.stop();
      print('');
      print('▶ FULL PIPELINE — ${files.length} files in '
          '${fmtMs(sw.elapsedMilliseconds)}');
      separator();
      expect(controller.state.status, isA<DicomViewerReady>());
    });
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 5 ▸ Scrubbing
  // ──────────────────────────────────────────────────────────
  group('5 ▸ Rapid Scrubbing Simulation', () {
    test('Bidirectional setFrame across files-source document', () async {
      final files = await loadSeries(seriesPath);
      final paths = files.map((e) => e.path).toList();
      final controller = DefaultDicomViewerController();
      addTearDown(controller.dispose);
      await controller.load(DicomSource.files(paths));
      final count = controller.state.frameCount;
      expect(count, files.length);

      final sw = Stopwatch()..start();
      var ops = 0;
      for (var r = 0; r < 3; r++) {
        for (var i = 0; i < count; i++) {
          await controller.setFrame(i);
          ops++;
        }
        for (var i = count - 1; i >= 0; i--) {
          await controller.setFrame(i);
          ops++;
        }
      }
      sw.stop();
      final perSec = ops / (sw.elapsedMicroseconds / 1e6);
      print('');
      print('▶ SCRUBBING — $ops frames in ${fmtMs(sw.elapsedMilliseconds)} '
          '(${perSec.toStringAsFixed(1)} ops/s)');
      separator();
      expect(perSec, greaterThan(10));
    });
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 6 ▸ Lifecycle
  // ──────────────────────────────────────────────────────────
  group('6 ▸ Controller Lifecycle & Cleanup', () {
    test('Create → load → dispose across the series', () async {
      final files = await loadSeries(seriesPath);
      final sw = Stopwatch()..start();
      for (final file in files.take(20)) {
        final controller = DefaultDicomViewerController();
        await controller.load(DicomSource.file(file.path));
        expect(controller.state.status, isA<DicomViewerReady>());
        controller.dispose();
      }
      sw.stop();
      print('');
      print('▶ LIFECYCLE — 20 controllers in ${fmtMs(sw.elapsedMilliseconds)}');
      separator();
    });
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 7 ▸ Edge Cases
  // ──────────────────────────────────────────────────────────
  group('7 ▸ Edge Cases & Robustness', () {
    test('Extreme windowing values stay safe', () async {
      final files = await loadSeries(seriesPath);
      final controller = DefaultDicomViewerController();
      addTearDown(controller.dispose);
      await controller.load(DicomSource.file(files.first.path));
      controller.setWindow(const DicomWindow(center: 1e12, width: 8000));
      controller.setWindow(const DicomWindow(center: -1e12, width: 1));
      expect(controller.state.status, isA<DicomViewerReady>());
    });

    test('Double reset does not crash', () async {
      final files = await loadSeries(seriesPath);
      final controller = DefaultDicomViewerController();
      addTearDown(controller.dispose);
      await controller.load(DicomSource.file(files.first.path));
      controller.reset();
      controller.reset();
      expect(controller.state.status, isA<DicomViewerReady>());
    });

    test('Missing file surfaces a typed error', () async {
      final controller = DefaultDicomViewerController();
      addTearDown(controller.dispose);
      try {
        await controller.load(const DicomSource.file('nope.dcm'));
        fail('expected an exception');
      } catch (e) {
        expect(e, isA<DicomException>());
      }
      expect(controller.state.status, isA<DicomViewerError>());
    });
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 8 ▸ Burst loads
  // ──────────────────────────────────────────────────────────
  group('8 ▸ Sequential Burst (Fast-Consecutive Loads)', () {
    test('Reload same file repeatedly (no stale state)', () async {
      final files = await loadSeries(seriesPath);
      final controller = DefaultDicomViewerController();
      addTearDown(controller.dispose);
      for (var i = 0; i < 10; i++) {
        await controller.load(DicomSource.file(files.first.path));
        expect(controller.state.status, isA<DicomViewerReady>());
      }
      expect(controller.state.currentFrame, 0);
    });
  });
}
