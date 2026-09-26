import 'dart:async';

/// Cine playback controller — timing owned by the scheduler.
abstract interface class DicomCineController {
  /// Whether playback is currently running.
  bool get playing;

  /// Playback rate in frames per second.
  double get fps;

  /// Starts playback from the first frame.
  Future<void> play({required final int frameCount, final bool loop = true});

  /// Pauses playback, keeping the current position.
  void pause();

  /// Stops playback and releases the scheduler subscription.
  void stop();

  /// Updates the playback rate, clamped to 1–60 fps.
  void setFps(final double fps);

  /// Loop flag used by the most recent [play] call.
  bool get loop;

  /// Releases scheduler resources.
  void dispose();
}

/// Cine frame scheduler — deterministic and testable.
abstract interface class DicomCineScheduler {
  /// Emits frame indices at [fps], optionally looping.
  Stream<int> frames({
    required final int frameCount,
    required final double fps,
    required final bool loop,
  });
}

/// Wall-clock scheduler backed by [Stream.periodic].
final class TimerDicomCineScheduler implements DicomCineScheduler {
  /// Creates a wall-clock cine scheduler.
  const TimerDicomCineScheduler();

  @override
  Stream<int> frames({
    required final int frameCount,
    required final double fps,
    required final bool loop,
  }) async* {
    if (frameCount <= 0 || fps <= 0) return;
    final period = Duration(microseconds: (1000000 / fps).round());
    var index = 0;
    await for (final _ in Stream.periodic(period)) {
      yield index;
      index++;
      if (index >= frameCount) {
        if (!loop) break;
        index = 0;
      }
    }
  }
}

/// Default cine controller driving frame callbacks from the scheduler.
final class DefaultDicomCineController implements DicomCineController {
  /// Creates a controller emitting scheduled indices to [onFrame].
  DefaultDicomCineController({
    required this.onFrame,
    final DicomCineScheduler? scheduler,
  }) : _scheduler = scheduler ?? const TimerDicomCineScheduler();

  final DicomCineScheduler _scheduler;

  /// Called for every scheduled frame index.
  final Future<void> Function(int index) onFrame;

  StreamSubscription<int>? _subscription;
  double _fps = 24;
  bool _loop = true;

  @override
  bool get playing => _subscription != null;

  @override
  double get fps => _fps;

  @override
  bool get loop => _loop;

  @override
  Future<void> play(
      {required final int frameCount, final bool loop = true}) async {
    await stop();
    _loop = loop;
    _subscription = _scheduler
        .frames(frameCount: frameCount, fps: _fps, loop: loop)
        .listen((final index) => onFrame(index));
  }

  @override
  void pause() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  @override
  void setFps(final double fps) {
    if (fps <= 0) return;
    _fps = fps.clamp(1.0, 60.0);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
