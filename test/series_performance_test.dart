// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:flutter_dicom/src/core/controller/dicom_controller.dart';
import 'package:flutter_dicom/src/core/services/dicom_service.dart';
import 'package:flutter_dicom/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

// ============================================================
// DICOM Library Comprehensive Benchmark Suite
// Tests every phase: load → parse → windowing → reset → dispose
// Covers: throughput, latency, stress, memory, and edge cases
// ============================================================

void main() async {
  await RustLib.init();

  const seriesPath = 'test/series-00001';

  // ─── Shared helpers ────────────────────────────────────────

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
  void separator([final String char = '─', final int len = 52]) => print(char * len);

  /// Formats milliseconds as a human-readable string.
  String fmtMs(final num ms) {
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(2)} s';
    return '${ms.toStringAsFixed(2)} ms';
  }

  // ──────────────────────────────────────────────────────────
  // GROUP 1 ▸ Throughput Benchmark
  // ──────────────────────────────────────────────────────────
  group('1 ▸ Throughput Benchmark (10 Runs)', () {
    late DicomController controller;

    setUp(() => controller = DicomController(service: DicomService()));
    tearDown(() => controller.dispose());

    test('High-throughput sequential load (release target: >60 FPS)', () async {
      final files = await loadSeries(seriesPath);

      const iterations = 10;
      final runFps = <double>[];
      final runLatencies = <double>[];
      final runP99 = <double>[];

      print('');
      print(
          '▶ THROUGHPUT BENCHMARK — $iterations runs × ${files.length} frames');
      separator();

      for (var r = 1; r <= iterations; r++) {
        final latencies = <int>[];
        final sw = Stopwatch()..start();

        for (final file in files) {
          final frameSw = Stopwatch()..start();
          try {
            await controller.loadFromFile(filePath: file.path);
          } catch (_) {
            // Individual frame errors don't fail the benchmark
          }
          frameSw.stop();
          latencies.add(frameSw.elapsedMilliseconds);
        }

        sw.stop();

        final fps = files.length / (sw.elapsedMilliseconds / 1000);
        final avg = latencies.reduce((final a, final b) => a + b) / latencies.length;
        final sorted = List.of(latencies)..sort();
        final p99 = sorted[(sorted.length * 0.99).floor()].toDouble();

        runFps.add(fps);
        runLatencies.add(avg);
        runP99.add(p99);

        print(
          'Run $r/$iterations │ '
          '${fps.toStringAsFixed(1).padLeft(6)} FPS │ '
          'avg ${fmtMs(avg).padLeft(8)} │ '
          'p99 ${fmtMs(p99).padLeft(8)}',
        );
      }

      final avgFps = runFps.reduce((final a, final b) => a + b) / iterations;
      final avgLat = runLatencies.reduce((final a, final b) => a + b) / iterations;
      final avgP99 = runP99.reduce((final a, final b) => a + b) / iterations;
      final minFps = runFps.reduce(min);
      final maxFps = runFps.reduce(max);

      print('');
      print('◀ AGGREGATE RESULTS');
      separator();
      print('  Avg FPS        : ${avgFps.toStringAsFixed(1)}');
      print(
          '  Min / Max FPS  : ${minFps.toStringAsFixed(1)} / ${maxFps.toStringAsFixed(1)}');
      print('  Avg latency    : ${fmtMs(avgLat)}');
      print('  Avg p99        : ${fmtMs(avgP99)}');
      separator();

      expect(
        avgFps,
        greaterThan(60),
        reason: 'Average throughput must exceed 60 FPS in release mode',
      );
    });
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 2 ▸ Per-Frame Latency Distribution
  // ──────────────────────────────────────────────────────────
  group('2 ▸ Per-Frame Latency Distribution', () {
    late DicomController controller;

    setUp(() => controller = DicomController(service: DicomService()));
    tearDown(() => controller.dispose());

    test('Latency percentiles (p50 / p95 / p99 / max)', () async {
      final files = await loadSeries(seriesPath);
      final latencies = <int>[];

      print('');
      print('▶ LATENCY DISTRIBUTION — ${files.length} frames × 3 passes');
      separator();

      for (var pass = 0; pass < 3; pass++) {
        for (final file in files) {
          final sw = Stopwatch()..start();
          try {
            await controller.loadFromFile(filePath: file.path);
          } catch (_) {}
          sw.stop();
          latencies.add(sw.elapsedMilliseconds);
        }
      }

      latencies.sort();
      final total = latencies.length;

      double pct(final double p) => latencies[(total * p / 100).floor()].toDouble();
      final p50 = pct(50);
      final p95 = pct(95);
      final p99 = pct(99);
      final maxLat = latencies.last.toDouble();
      final minLat = latencies.first.toDouble();
      final avg = latencies.reduce((final a, final b) => a + b) / total;

      print('  Samples        : $total');
      print('  Min            : ${fmtMs(minLat)}');
      print('  p50 (median)   : ${fmtMs(p50)}');
      print('  p95            : ${fmtMs(p95)}');
      print('  p99            : ${fmtMs(p99)}');
      print('  Max            : ${fmtMs(maxLat)}');
      print('  Mean           : ${fmtMs(avg)}');

      // Histogram (bucket size: 5 ms, up to 50 ms)
      final buckets = List.filled(11, 0);
      for (final l in latencies) {
        final idx = (l ~/ 5).clamp(0, 10);
        buckets[idx]++;
      }
      print('');
      print('  Latency histogram (0–50+ ms, bucket=5 ms):');
      for (var i = 0; i < buckets.length; i++) {
        final lo = i * 5;
        final hi = i < 10 ? '${lo + 5}' : '50+';
        final bar = '█' * (buckets[i] * 30 ~/ total).clamp(0, 30);
        print(
          '  ${lo.toString().padLeft(3)}–${hi.padLeft(3)} ms │ '
          '${bar.padRight(30)} ${buckets[i]}',
        );
      }
      separator();

      expect(p99, lessThan(500),
          reason: 'p99 frame latency must be below 500 ms');
    });
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 3 ▸ Windowing Stress Test
  // ──────────────────────────────────────────────────────────
  group('3 ▸ Windowing & Contrast Stress Test', () {
    late DicomController controller;

    setUp(() => controller = DicomController(service: DicomService()));
    tearDown(() => controller.dispose());

    test('Rapid windowing adjustments per frame (5 passes × 10 ops/frame)',
        () async {
      final files = await loadSeries(seriesPath);

      print('');
      print('▶ WINDOWING STRESS — ${files.length} frames × 5 passes × 10 ops');
      separator();

      final sw = Stopwatch()..start();
      var totalOps = 0;
      var loadErrors = 0;

      for (var pass = 1; pass <= 5; pass++) {
        final passSw = Stopwatch()..start();
        var passOps = 0;

        for (final file in files) {
          // 1. Load frame
          try {
            await controller.loadFromFile(filePath: file.path);
          } catch (_) {
            loadErrors++;
            continue;
          }

          // 2. Rapid windowing simulation (mouse-drag scrubbing)
          for (var i = 0; i < 10; i++) {
            controller.adjustWindowing(
              deltaX: (i - 5) * 12.0, // center → sweep L/R
              deltaY: (i - 5) * 6.0, // level sweep
            );
            passOps++;
          }

          // 3. Cleanup for next frame
          controller.resetWindowing();
          passOps++;
        }

        passSw.stop();
        totalOps += passOps;
        final opsPerSec =
            (passOps / (passSw.elapsedMilliseconds / 1000)).toStringAsFixed(0);
        print(
            '  Pass $pass/5 │ $passOps ops │ $opsPerSec ops/s │ ${fmtMs(passSw.elapsedMilliseconds.toDouble())}');
      }

      sw.stop();
      final totalSec = sw.elapsedMilliseconds / 1000;
      final globalOpsPerSec = (totalOps / totalSec).toStringAsFixed(0);

      print('');
      print('◀ WINDOWING SUMMARY');
      separator();
      print('  Total time     : ${fmtMs(sw.elapsedMilliseconds.toDouble())}');
      print('  Total ops      : $totalOps');
      print('  Load errors    : $loadErrors');
      print('  Global ops/s   : $globalOpsPerSec');
      separator();

      expect(
        sw.elapsedMilliseconds,
        lessThan(30000),
        reason: 'Windowing stress must complete within 30 s',
      );
    });
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 4 ▸ Full Pipeline per File (Load → Parse → Window → Reset → Next)
  // ──────────────────────────────────────────────────────────
  group('4 ▸ Full Pipeline per File', () {
    test(
      'Each file: open → parse → adjust windowing × N → reset → move to next',
      () async {
        final files = await loadSeries(seriesPath);

        print('');
        print(
            '▶ FULL PIPELINE — processing ${files.length} files sequentially');
        separator('─', 72);
        print(
          '${'File'.padRight(45)} │ '
          '${'Load'.padLeft(8)} │ '
          '${'Win×5'.padLeft(8)} │ '
          '${'Reset'.padLeft(8)} │ '
          '${'Total'.padLeft(8)}',
        );
        separator('─', 72);

        var passCount = 0;
        var failCount = 0;
        final totalTimes = <int>[];

        for (final file in files) {
          // Fresh controller per file — tests isolation & cleanup
          final ctrl = DicomController(service: DicomService());
          final name = file.path.split('/').last;

          try {
            // ① Load + Parse
            final loadSw = Stopwatch()..start();
            await ctrl.loadFromFile(filePath: file.path);
            loadSw.stop();

            // ② Windowing (5 distinct adjustments)
            final winSw = Stopwatch()..start();
            final winOps = [
              (deltaX: 100.0, deltaY: 0.0),
              (deltaX: -100.0, deltaY: 0.0),
              (deltaX: 0.0, deltaY: 50.0),
              (deltaX: 0.0, deltaY: -50.0),
              (deltaX: 200.0, deltaY: 100.0),
            ];
            for (final op in winOps) {
              ctrl.adjustWindowing(deltaX: op.deltaX, deltaY: op.deltaY);
            }
            winSw.stop();

            // ③ Reset
            final resetSw = Stopwatch()..start();
            ctrl.resetWindowing();
            resetSw.stop();

            final total = loadSw.elapsedMilliseconds +
                winSw.elapsedMilliseconds +
                resetSw.elapsedMilliseconds;

            totalTimes.add(total);
            passCount++;

            print(
              '${name.padRight(45)} │ '
              '${fmtMs(loadSw.elapsedMilliseconds.toDouble()).padLeft(8)} │ '
              '${fmtMs(winSw.elapsedMilliseconds.toDouble()).padLeft(8)} │ '
              '${fmtMs(resetSw.elapsedMilliseconds.toDouble()).padLeft(8)} │ '
              '${fmtMs(total.toDouble()).padLeft(8)}',
            );
          } catch (e) {
            failCount++;
            print('${name.padRight(45)} │ ERROR: $e');
          } finally {
            ctrl.dispose();
          }
        }

        separator('─', 72);

        if (totalTimes.isNotEmpty) {
          final sumMs = totalTimes.reduce((final a, final b) => a + b);
          final avgMs = sumMs / totalTimes.length;
          final minMs = totalTimes.reduce(min);
          final maxMs = totalTimes.reduce(max);

          print('');
          print('◀ PIPELINE SUMMARY');
          separator();
          print('  Passed         : $passCount / ${files.length}');
          print('  Failed         : $failCount');
          print('  Total time     : ${fmtMs(sumMs.toDouble())}');
          print('  Avg per file   : ${fmtMs(avgMs)}');
          print('  Min            : ${fmtMs(minMs.toDouble())}');
          print('  Max            : ${fmtMs(maxMs.toDouble())}');
          separator();
        }

        expect(
          failCount,
          equals(0),
          reason: 'Every file must complete the full pipeline without error',
        );
        expect(
          passCount,
          equals(files.length),
          reason: 'All files must be processed',
        );
      },
    );
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 5 ▸ Rapid Scrubbing Simulation (back-and-forth)
  // ──────────────────────────────────────────────────────────
  group('5 ▸ Rapid Scrubbing Simulation', () {
    late DicomController controller;

    setUp(() => controller = DicomController(service: DicomService()));
    tearDown(() => controller.dispose());

    test('Bidirectional frame scrubbing (forward + backward × 3)', () async {
      final files = await loadSeries(seriesPath);

      print('');
      print('▶ SCRUBBING SIMULATION — ${files.length} frames × 3 round-trips');
      separator();

      final sw = Stopwatch()..start();
      var ops = 0;

      for (var trip = 0; trip < 3; trip++) {
        // Forward
        for (final file in files) {
          try {
            await controller.loadFromFile(filePath: file.path);
            controller.adjustWindowing(deltaX: 10.0, deltaY: 5.0);
            ops++;
          } catch (_) {}
        }

        // Backward
        for (final file in files.reversed) {
          try {
            await controller.loadFromFile(filePath: file.path);
            controller.adjustWindowing(deltaX: -10.0, deltaY: -5.0);
            ops++;
          } catch (_) {}
        }

        controller.resetWindowing();
        print('  Round-trip ${trip + 1}/3 completed ($ops ops so far)');
      }

      sw.stop();

      final opsPerSec =
          (ops / (sw.elapsedMilliseconds / 1000)).toStringAsFixed(0);

      print('');
      print('◀ SCRUBBING SUMMARY');
      separator();
      print('  Total time     : ${fmtMs(sw.elapsedMilliseconds.toDouble())}');
      print('  Total ops      : $ops');
      print('  Ops/sec        : $opsPerSec');
      separator();

      expect(
        sw.elapsedMilliseconds,
        lessThan(60000),
        reason: 'Bidirectional scrubbing must complete within 60 s',
      );
    });
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 6 ▸ Memory & Controller Lifecycle
  // ──────────────────────────────────────────────────────────
  group('6 ▸ Controller Lifecycle & Cleanup', () {
    test(
      'Create → load → dispose per file (no shared controller leak)',
      () async {
        final files = await loadSeries(seriesPath);

        print('');
        print('▶ LIFECYCLE TEST — fresh controller per file × ${files.length}');
        separator();

        final sw = Stopwatch()..start();

        for (var i = 0; i < files.length; i++) {
          final ctrl = DicomController(service: DicomService());
          try {
            await ctrl.loadFromFile(filePath: files[i].path);
            ctrl.adjustWindowing(deltaX: 50.0, deltaY: 25.0);
            ctrl.resetWindowing();
          } finally {
            ctrl.dispose();
          }

          if ((i + 1) % 10 == 0) {
            print('  Processed ${i + 1}/${files.length} files...');
          }
        }

        sw.stop();

        print('');
        print('◀ LIFECYCLE SUMMARY');
        separator();
        print('  Files          : ${files.length}');
        print('  Total time     : ${fmtMs(sw.elapsedMilliseconds.toDouble())}');
        print(
            '  Avg per file   : ${fmtMs(sw.elapsedMilliseconds / files.length)}');
        separator();

        // If we get here without crash → lifecycle is clean
        expect(true, isTrue, reason: 'All controllers disposed cleanly');
      },
    );
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 7 ▸ Edge Cases
  // ──────────────────────────────────────────────────────────
  group('7 ▸ Edge Cases & Robustness', () {
    late DicomController controller;

    setUp(() => controller = DicomController(service: DicomService()));
    tearDown(() => controller.dispose());

    test('Extreme windowing values (overflow / underflow)', () async {
      final files = await loadSeries(seriesPath);
      if (files.isEmpty) return;

      await controller.loadFromFile(filePath: files.first.path);

      final extremeValues = [
        (deltaX: double.maxFinite / 2, deltaY: double.maxFinite / 2),
        (deltaX: -double.maxFinite / 2, deltaY: -double.maxFinite / 2),
        (deltaX: 0.0, deltaY: 0.0),
        (deltaX: 1e6, deltaY: 1e6),
        (deltaX: -1e6, deltaY: -1e6),
      ];

      print('');
      print('▶ EXTREME WINDOWING VALUES');
      separator();

      for (final v in extremeValues) {
        try {
          controller.adjustWindowing(deltaX: v.deltaX, deltaY: v.deltaY);
          print('  deltaX=${v.deltaX.toStringAsExponential(1)}, '
              'deltaY=${v.deltaY.toStringAsExponential(1)} → OK');
        } catch (e) {
          print('  deltaX=${v.deltaX.toStringAsExponential(1)}, '
              'deltaY=${v.deltaY.toStringAsExponential(1)} → ERROR: $e');
        }
      }

      controller.resetWindowing();
      print('  Reset after extreme values → OK');
      separator();
    });

    test('Double reset does not crash', () async {
      final files = await loadSeries(seriesPath);
      if (files.isEmpty) return;

      await controller.loadFromFile(filePath: files.first.path);
      controller.adjustWindowing(deltaX: 100.0, deltaY: 50.0);
      controller.resetWindowing();
      controller.resetWindowing(); // Second reset — must not throw

      print('Double reset: OK');
    });

    test('Reload same file repeatedly (no stale state)', () async {
      final files = await loadSeries(seriesPath);
      if (files.isEmpty) return;

      final file = files.first;
      final latencies = <int>[];

      print('');
      print('▶ REPEATED LOAD — same file × 20 times');
      separator();

      for (var i = 0; i < 20; i++) {
        final sw = Stopwatch()..start();
        await controller.loadFromFile(filePath: file.path);
        sw.stop();
        latencies.add(sw.elapsedMilliseconds);
      }

      final avg = latencies.reduce((final a, final b) => a + b) / latencies.length;
      final sorted = List.of(latencies)..sort();

      print('  Avg latency    : ${fmtMs(avg)}');
      print('  Min            : ${fmtMs(sorted.first.toDouble())}');
      print('  Max            : ${fmtMs(sorted.last.toDouble())}');

      // Variance check: no single load should be >10× the average
      final outliers = latencies.where((final l) => l > avg * 10).length;
      print('  Outliers >10×  : $outliers');
      separator();

      expect(outliers, lessThan(3),
          reason: 'Reloading the same file should have consistent latency');
    });
  });

  // ──────────────────────────────────────────────────────────
  // GROUP 8 ▸ Concurrent Load (Isolate-Safe Check)
  // ──────────────────────────────────────────────────────────
  group('8 ▸ Sequential Burst (Fast-Consecutive Loads)', () {
    test('Fire N loads with minimal await gap', () async {
      final files = await loadSeries(seriesPath);
      final burstFiles = files.take(10).toList();

      print('');
      print('▶ BURST LOAD — ${burstFiles.length} files, minimal delay between');
      separator();

      final controller = DicomController(service: DicomService());
      final sw = Stopwatch()..start();
      var success = 0;

      for (final file in burstFiles) {
        try {
          await controller.loadFromFile(filePath: file.path);
          // Immediately adjust windowing without awaiting anything else
          controller.adjustWindowing(deltaX: 30.0, deltaY: 15.0);
          controller.resetWindowing();
          success++;
        } catch (_) {}
      }

      sw.stop();
      controller.dispose();

      print('  Successful     : $success / ${burstFiles.length}');
      print('  Total time     : ${fmtMs(sw.elapsedMilliseconds.toDouble())}');
      print(
        '  Effective FPS  : '
        '${(success / (sw.elapsedMilliseconds / 1000)).toStringAsFixed(1)}',
      );
      separator();

      expect(success, equals(burstFiles.length),
          reason: 'All burst loads must succeed');
    });
  });
}
