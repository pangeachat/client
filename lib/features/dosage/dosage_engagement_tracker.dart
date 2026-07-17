import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:fluffychat/features/dosage/dosage_engagement_span.dart';
import 'package:fluffychat/features/dosage/dosage_signal_identity.dart';
import 'package:fluffychat/features/dosage/dosage_signals_repo.dart';

/// Tracks foreground learner engagement as best-effort spans. A span opens on
/// the first learner activity (a sent message) and closes+flushes on the next
/// heartbeat, on backgrounding, on an idle gap, or when it would exceed the
/// server cap. Minutes are derived server-side from the interval union of
/// spans, so honest short windows are all this needs to report.
///
/// Fire-and-forget and never blocks the UI: a flush hands the span to
/// [DosageSignalsRepo] (itself best-effort, never-throw) without awaiting, and
/// the whole tracker is a no-op until [DosageSignalsRepo.isEnabled].
///
/// The single [instance] is driven by the analytics update service (heartbeat +
/// app-lifecycle) and by the chat send path ([recordActivity]). It is also
/// constructable with an injected clock + http client for tests.
class DosageEngagementTracker {
  /// Idle threshold: if no activity arrived within this window before a flush,
  /// the span closes at the last real activity rather than the flush time, so
  /// an idle tail is never counted as engagement.
  static const Duration idleGap = Duration(minutes: 2);

  /// A span that saw real activity represents at least this much engagement, so
  /// a single-message span isn't dropped as zero-length.
  static const Duration minEngagement = Duration(seconds: 60);

  final DateTime Function() _now;
  final http.Client? _httpClient;

  DosageEngagementTracker({DateTime Function()? now, http.Client? httpClient})
    : _now = now ?? DateTime.now,
      _httpClient = httpClient;

  /// Shared tracker used by the running app.
  static final DosageEngagementTracker instance = DosageEngagementTracker();

  String? _spanId;
  DateTime? _spanStart;
  DateTime? _lastActivity;
  String? _deviceId;
  String? _accessToken;

  /// Records one unit of learner activity (a sent message). Opens a span if
  /// none is open, extends the current one otherwise, and rolls over into a new
  /// span if the open one would exceed the server cap. No-op when disabled.
  void recordActivity({
    required String deviceId,
    required String? accessToken,
  }) {
    if (!DosageSignalsRepo.isEnabled) return;
    final DateTime t = _now().toUtc();

    if (_spanStart == null) {
      _openSpan(t, deviceId, accessToken);
      return;
    }

    if (t.difference(_spanStart!) >= DosageEngagementSpan.maxSpan) {
      _emit(_spanStart!.add(DosageEngagementSpan.maxSpan));
      _openSpan(t, deviceId, accessToken);
      return;
    }

    _lastActivity = t;
  }

  /// Closes and flushes the open span, if any (heartbeat, background, dispose).
  void flushOpenSpan() {
    if (_spanStart == null) return;
    _emit(_computeEnd(_now().toUtc()));
  }

  void _openSpan(DateTime t, String deviceId, String? accessToken) {
    _spanId = DosageSignalIdentity.uuidV4();
    _spanStart = t;
    _lastActivity = t;
    _deviceId = deviceId;
    _accessToken = accessToken;
  }

  /// The honest span end: the last activity when idle, else the flush time;
  /// floored to [minEngagement] and capped to the server's max span.
  DateTime _computeEnd(DateTime t) {
    final DateTime start = _spanStart!;
    final DateTime activityEnd = _lastActivity ?? start;
    final bool idle = t.difference(activityEnd) >= idleGap;
    DateTime end = idle ? activityEnd : t;

    final DateTime floor = start.add(minEngagement);
    if (end.isBefore(floor)) {
      end = floor.isBefore(t) ? floor : t;
    }
    final DateTime cap = start.add(DosageEngagementSpan.maxSpan);
    if (end.isAfter(cap)) end = cap;
    return end;
  }

  /// Snapshots and resets span state, then fire-and-forgets the POST. Resetting
  /// first makes a re-entrant flush a no-op and prevents any double-send.
  void _emit(DateTime end) {
    final String? spanId = _spanId;
    final DateTime? start = _spanStart;
    final String? deviceId = _deviceId;
    final String? accessToken = _accessToken;
    _spanId = null;
    _spanStart = null;
    _lastActivity = null;
    _deviceId = null;
    _accessToken = null;

    if (spanId == null || start == null || deviceId == null) return;
    if (!end.isAfter(start)) return;

    unawaited(
      DosageSignalsRepo.postEngagementSpans(
        spans: [
          DosageEngagementSpan(
            deviceId: deviceId,
            spanId: spanId,
            spanStart: start,
            spanEnd: end,
            platform: DosageSignalIdentity.platform(),
          ),
        ],
        accessToken: accessToken,
        client: _httpClient,
      ).catchError((_) {}),
    );
  }
}
