import 'package:fluffychat/features/dosage/dosage_audio_event.dart';

/// Measures ELAPSED PLAYBACK WALL CLOCK for one playback, start to end.
///
/// Not the asset's duration — that is what was *available*, not what was
/// *heard*. A learner who stops a 40-second message after 4 seconds heard 4
/// seconds, and no playback path in this app distinguishes "finished" from
/// "stopped", so the elapsed clock is the only honest magnitude available. It is
/// also correct under a changed playback speed: 10 s of audio at 2× is 5 s of
/// listening, and 5 s is what the wall clock reports.
///
/// Time accumulates ONLY while the player reports playing, so a pause banks
/// nothing and a paused-then-abandoned playback reports what was actually heard
/// rather than how long the widget was on screen.
///
/// Pure and Flutter-free so the accounting can be tested without a player, a
/// widget or a real clock.
class DosagePlaybackMeter {
  DosagePlaybackMeter({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  Duration _accumulated = Duration.zero;
  DateTime? _runningSince;

  /// Whether playback was EVER observed to start. Distinguishes "played for
  /// 0 ms" from "never played at all" — the second is a non-event and must emit
  /// nothing, which is how the silent-skip artefact is suppressed at its cause
  /// rather than by thresholding a real observation (D-V2-2).
  bool _started = false;

  bool get hasStarted => _started;

  /// Whether the clock is currently running.
  bool get isRunning => _runningSince != null;

  /// Elapsed so far, including the currently running interval.
  Duration get elapsed {
    final since = _runningSince;
    if (since == null) return _accumulated;
    return _accumulated + _interval(since, _now());
  }

  /// Feeds the player's playing/not-playing state. Idempotent in both
  /// directions, so a stream that repeats a state — which `playerStateStream`
  /// does on every buffering and position change — neither restarts nor
  /// double-counts an interval.
  void setPlaying(bool playing) {
    if (playing) {
      if (_runningSince != null) return;
      _started = true;
      _runningSince = _now();
      return;
    }
    final since = _runningSince;
    if (since == null) return;
    _accumulated += _interval(since, _now());
    _runningSince = null;
  }

  /// Closes the measurement and returns the total, or null when playback never
  /// started or measured nothing. Resets, so a re-entrant or duplicated finish
  /// (a stop transition immediately followed by dispose) returns null the second
  /// time and CANNOT emit the same playback twice.
  Duration? finish() {
    setPlaying(false);
    final bool started = _started;
    final Duration total = _accumulated;
    _accumulated = Duration.zero;
    _runningSince = null;
    _started = false;
    if (!started) return null;
    // A well-formedness filter, not a threshold: zero elapsed is nothing
    // measured, contributes nothing to a sum of minutes, and the ingest models
    // a playback as a positive magnitude.
    if (total <= Duration.zero) return null;
    return total;
  }

  /// One interval, floored at zero and capped at the event ceiling. The clock is
  /// wall time, so an NTP correction or a timezone change mid-playback can move
  /// it backwards or far forwards; neither may produce a negative magnitude or
  /// an absurd one.
  Duration _interval(DateTime from, DateTime to) {
    final Duration delta = to.difference(from);
    if (delta.isNegative) return Duration.zero;
    const Duration ceiling = Duration(
      milliseconds: DosageAudioEvent.maxElapsedMs,
    );
    return delta > ceiling ? ceiling : delta;
  }
}
