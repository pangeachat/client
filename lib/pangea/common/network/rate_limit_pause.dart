import 'package:flutter/foundation.dart';

import 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// A read that was suppressed by a [RateLimitPause] rather than attempted.
///
/// Typed so a caller can tell "we deliberately did not ask" from "the request
/// failed": the two want opposite handling on a display surface — a failure
/// may empty it, a suppression must leave what is already there alone. The
/// `toString()` matters for the same reason it does on `MissingQuestException`
/// — without it any report arrives in Sentry as
/// `Instance of 'RateLimitedException'` (repos-and-error-handling doc).
class RateLimitedException implements Exception {
  @override
  String toString() =>
      'RateLimitedException: read suppressed — the backend returned 429';
}

/// A repo-wide pause after the backend rate-limits us (HTTP 429).
///
/// A 429 is a statement about RATE, not about the key that happened to see it,
/// so it pauses every read on the budget rather than that one key. Per-key
/// backoff structurally cannot honour it: the world map hydrates one key per
/// visible pin, so K keys each backing off independently still emit
/// K/cooldown requests — at the 2026-08-04 incident's K=104 that is 104/min
/// against a 60/min budget, still saturated. Only a pause that ignores the key
/// restores the invariant "we stop when the server says stop", independent of
/// K. `ActivityPlanRepo` reached the same conclusion first (#8160) and keeps
/// its equivalent state inline.
///
/// **One instance per budget, never one global instance.** Choreo meters
/// `/choreo` and `/subscription` separately, so an activity 429 must never
/// stall checkout. The boundary that matters is the budget, not the class:
/// reads that the same limiter counts together share an instance, and reads it
/// counts apart never do.
class RateLimitPause {
  RateLimitPause([this.duration = defaultDuration]);

  /// Matches the pause `ActivityPlanRepo` applies to the sibling activity read
  /// and the window choreo's limiter meters over.
  static const Duration defaultDuration = Duration(seconds: 60);

  final Duration duration;

  /// Earliest wall-clock time reads on this budget may resume.
  DateTime? _until;

  /// Test seam: the pause's clock. Backoff is wall-clock, so tests would
  /// otherwise need real delays.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// Whether reads on this budget are currently suppressed. Clears itself once
  /// the window has lapsed — a throttle is transient, never terminal.
  bool get isPaused {
    final until = _until;
    if (until == null) return false;
    if (now().isBefore(until)) return true;
    _until = null;
    return false;
  }

  /// Starts the pause when [error] is the backend asking us to stop (429).
  /// Any other failure says something about the request, not about our rate:
  /// pausing on those would let one bad row take down every read on the
  /// budget.
  void recordFailure(Object? error) {
    if (PangeaHttpException.statusCodeOf(error) == 429) {
      _until = now().add(duration);
    }
  }

  /// The [_until] this pause's suppression was last reported for. Distinct
  /// from [_until] itself: a pause is armed and cleared many times over a
  /// session (every 429 restarts it), and every read suppressed during ONE
  /// window must collapse into a single Sentry event — reporting every
  /// suppressed read would spend the event budget as fast as the reads that
  /// got suppressed (a camera pan alone can hit this dozens of times), while
  /// reporting once per app session would go silent across a whole session of
  /// intermittent 429s (client#8507).
  DateTime? _lastReportedUntil;

  /// Reports this pause's OWN suppression to Sentry at `info` — visibility
  /// that a read was deliberately skipped, not an error, since the 429 that
  /// armed the pause was already captured once by [recordFailure]'s caller.
  /// No-ops when not currently paused, or when this activation ([_until]) was
  /// already reported. Returns whether this call actually reported — the seam
  /// tests assert on, same pattern as `reportCourseOutlineFailure`.
  ///
  /// Call from inside the repo method at the exact point it returns
  /// [RateLimitedException] instead of asking — that keeps this the repo's
  /// report, not a caller's (repos-and-error-handling.instructions.md § the
  /// repo reports, the caller does not). [data] is repo-specific context
  /// (quest id, viewport bounds, ...) attached to the one event the
  /// activation gets.
  bool reportSuppressionOnce(Map<String, dynamic> data) {
    final until = _until;
    if (until == null || _lastReportedUntil == until) return false;
    _lastReportedUntil = until;
    ErrorHandler.logError(
      e: RateLimitedException(),
      s: StackTrace.current,
      data: data,
      level: SentryLevel.info,
    );
    return true;
  }

  /// Drops the pause. For tests, and for an explicit user-initiated refresh,
  /// which must never be suppressed. Also clears the report gate so a fresh
  /// activation after this point gets its own event rather than being read as
  /// a repeat of whatever was last reported.
  void reset() {
    _until = null;
    _lastReportedUntil = null;
  }
}
