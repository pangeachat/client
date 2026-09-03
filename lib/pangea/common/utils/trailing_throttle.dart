import 'dart:async';

/// Runs an action at most once per [window] without ever dropping the last
/// trigger: a call that lands inside the window, or while a run is still in
/// flight, queues exactly ONE follow-up run for when both have cleared, and
/// calls that land while that follow-up is queued fold into it.
///
/// A throttle that drops instead of trailing loses the last trigger of a
/// burst — the sync tick that should have refreshed a view arrives 2s after
/// the previous refresh and is thrown away, and nothing re-runs until some
/// unrelated trigger happens along (#8735).
class TrailingThrottle {
  TrailingThrottle(this.window);

  final Duration window;

  /// The in-flight run, settled (never erroring) so a queued follow-up only
  /// waits for it; the run's own error still reaches its caller.
  Future<void>? _inFlight;

  /// Open from a run's start until [window] has elapsed.
  Completer<void>? _windowCloses;

  bool _followUpQueued = false;

  Future<void> run(Future<void> Function() action) async {
    if (_followUpQueued) return;
    final inFlight = _inFlight;
    if (inFlight != null || _windowCloses != null) {
      _followUpQueued = true;
      try {
        if (inFlight != null) await inFlight;
        final windowCloses = _windowCloses;
        if (windowCloses != null) await windowCloses.future;
      } finally {
        _followUpQueued = false;
      }
    }

    final windowCloses = _windowCloses = Completer<void>();
    Timer(window, () {
      windowCloses.complete();
      if (identical(_windowCloses, windowCloses)) _windowCloses = null;
    });

    final current = action();
    final settled = current.then((_) {}, onError: (_) {});
    _inFlight = settled;
    try {
      await current;
    } finally {
      // A queued follow-up may already have started its own run by the time
      // this one's caller resumes; only clear our own marker.
      if (identical(_inFlight, settled)) _inFlight = null;
    }
  }
}
