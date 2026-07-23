import 'dart:async';

import 'package:flutter/foundation.dart';

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
/// PER-ACCOUNT: one tracker per logged-in account, resolved via [forAccount] and
/// disposed via [disposeAccount]. The app runs multiple Matrix accounts, so a
/// single shared tracker would let one account's teardown flush/attribute
/// another's span; keeping a tracker per account isolates them. Each account's
/// analytics service drives + disposes ITS tracker.
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

  /// Per-account trackers, keyed by account (mxid). Each account gets its own so
  /// one account's teardown never flushes or attributes another's spans.
  static final Map<String, DosageEngagementTracker> _byAccount = {};

  /// Accounts whose teardown is in flight. While closing, [forAccount] must not
  /// recreate a tracker — otherwise a send resolving concurrently with logout
  /// would open a fresh span that no one ever flushes (its bearer is about to be
  /// invalidated).
  static final Set<String> _closing = {};

  /// The tracker for [userId], created on first use. Returns none for an unknown
  /// account (empty userId) or one whose teardown is in flight — the caller then
  /// records no engagement (the envelope still posts) rather than attributing a
  /// span to an unknown or closing account.
  static DosageEngagementTracker? forAccount(String userId) {
    if (userId.isEmpty || _closing.contains(userId)) return null;
    return _byAccount.putIfAbsent(userId, DosageEngagementTracker.new);
  }

  /// Flushes + drops [userId]'s tracker on that account's teardown. Awaited so
  /// the last span is sent (under the still-valid bearer) BEFORE logout
  /// invalidates it; one account's teardown can't touch another's tracker;
  /// tombstoned throughout so a concurrent send can't recreate it. Idempotent.
  static Future<void> disposeAccount(String userId) async {
    if (userId.isEmpty) return;
    _closing.add(userId);
    try {
      await _byAccount.remove(userId)?.flushOpenSpan();
    } finally {
      _closing.remove(userId);
    }
  }

  /// Seeds a tracker for [userId] (tests only), so a teardown path can be driven
  /// against a controllable tracker.
  @visibleForTesting
  static void debugPutAccount(String userId, DosageEngagementTracker tracker) =>
      _byAccount[userId] = tracker;

  /// Clears the per-account registry (tests only) so the app-global map doesn't
  /// leak between tests.
  @visibleForTesting
  static void debugResetAccounts() {
    _byAccount.clear();
    _closing.clear();
  }

  String? _spanId;
  DateTime? _spanStart;
  DateTime? _lastActivity;
  String? _userId;
  String? _deviceId;
  String? _accessToken;

  /// Records one unit of learner activity (a sent message). Opens a span if
  /// none is open, extends the current one otherwise, and rolls over into a new
  /// span if the open one would exceed the server cap. No-op when disabled.
  ///
  /// [userId] is the account (mxid) whose activity this is; the tracker is an
  /// app-isolate-global singleton shared across every logged-in account, so it
  /// keys spans on the ACCOUNT identity — two accounts that happen to share a
  /// device id must not merge, and a span must flush under its own account's
  /// bearer, never a later account's.
  void recordActivity({
    required String userId,
    required String deviceId,
    required String? accessToken,
  }) {
    if (!DosageSignalsRepo.isEnabled) return;
    // A span needs a device id (the repo drops spans without one). Skip until it
    // is known rather than open a span that would be silently rejected — the
    // next activity with a resolved device id opens one.
    if (deviceId.isEmpty) return;
    final DateTime t = _now().toUtc();

    if (_spanStart == null) {
      _openSpan(t, userId, deviceId, accessToken);
      return;
    }

    // Account switch: a span is attributed to ONE account (its userId + device
    // + bearer token). If this activity is from a DIFFERENT account or device,
    // close the prior span under ITS OWN account and open a fresh one here —
    // never let account B's activity extend account A's span or flush under A's
    // token. Keyed on userId (not device alone), so two accounts sharing a
    // per-user device id still roll over.
    if (userId != _userId || deviceId != _deviceId) {
      unawaited(_emit(_computeEnd(t)));
      _openSpan(t, userId, deviceId, accessToken);
      return;
    }

    // Same account: keep the freshest token for the eventual flush. Tokens
    // refresh mid-span, and a stale one would post the span under an expired
    // bearer.
    _accessToken = accessToken;

    // Idle-gap rollover: the time since the last activity is idle, not
    // engagement. If this activity lands after the idle threshold, close the
    // prior span at its honest end (the last activity, floored) and start a
    // FRESH span here — never bridge the idle gap into one span. Checked before
    // the cap so a lone activity followed much later by another rolls over
    // (a short span + a new span) instead of reporting a full capped span of
    // mostly-idle time.
    if (t.difference(_lastActivity ?? _spanStart!) >= idleGap) {
      unawaited(_emit(_computeEnd(t)));
      _openSpan(t, userId, deviceId, accessToken);
      return;
    }

    // Cap rollover: a CONTINUOUSLY active span (gaps under the idle threshold)
    // must not exceed the server max — close it at the cap and roll over.
    if (t.difference(_spanStart!) >= DosageEngagementSpan.maxSpan) {
      unawaited(_emit(_spanStart!.add(DosageEngagementSpan.maxSpan)));
      _openSpan(t, userId, deviceId, accessToken);
      return;
    }

    _lastActivity = t;
  }

  /// Closes and flushes the open span, if any (heartbeat, background, dispose).
  /// Returns the flush's POST future so teardown can AWAIT the final flush
  /// rather than drop it; heartbeat/background callers fire-and-forget.
  Future<void> flushOpenSpan() {
    if (_spanStart == null) return Future.value();
    return _emit(_computeEnd(_now().toUtc()));
  }

  void _openSpan(
    DateTime t,
    String userId,
    String deviceId,
    String? accessToken,
  ) {
    _spanId = DosageSignalIdentity.uuidV4();
    _spanStart = t;
    _lastActivity = t;
    _userId = userId;
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

  /// Snapshots and resets span state, then POSTs the span. Resetting first makes
  /// a re-entrant flush a no-op and prevents any double-send. Returns the POST
  /// future (already error-swallowing) so a caller can await it; rollover
  /// callers discard it (fire-and-forget).
  Future<void> _emit(DateTime end) {
    final String? spanId = _spanId;
    final DateTime? start = _spanStart;
    final String? deviceId = _deviceId;
    final String? accessToken = _accessToken;
    _spanId = null;
    _spanStart = null;
    _lastActivity = null;
    _userId = null;
    _deviceId = null;
    _accessToken = null;

    if (spanId == null || start == null || deviceId == null) {
      return Future.value();
    }
    if (!end.isAfter(start)) return Future.value();

    return DosageSignalsRepo.postEngagementSpans(
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
    ).catchError((_) {});
  }
}
