import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/dosage/dosage_engagement_span.dart';
import 'package:fluffychat/features/dosage/dosage_message_event.dart';
import 'package:fluffychat/features/dosage/dosage_session_outcome.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Best-effort dual-write of a student's dosage signals to the teacher-BFF
/// (admin-dash-api) `POST /api/internal/dosage/{message-events,engagement-spans,
/// session-outcomes}`.
///
/// A sibling of [AnalyticsEventsRepo] with the identical contract — the Matrix
/// room / activity state stays the canonical source; these POSTs are a
/// low-latency provisional copy the server reconciles and verifies. Everything
/// here is best-effort:
///  * **Non-blocking / never throws.** Every failure path is swallowed and, at
///    most, logged at warning. Callers fire-and-forget; a failed POST can never
///    surface to the user or break the send / analytics / activity flow.
///  * **Ships dark, triple-gated.** A no-op unless [Environment.analyticsDualWriteEnabled]
///    AND [Environment.dosageSignalsEnabled] are set AND [Environment.teacherBffApi]
///    is configured. Dosage rides the same BFF door as the analytics dual-write,
///    so it inherits that flag plus its own.
///  * **Contract-exact body.** Each POST body is exactly `{ "<key>": [<item>...] }`
///    with each item the verbatim model `toJson`. The endpoint is `extra="forbid"`
///    and binds identity from the bearer token, so there is NO `sender` field and
///    no injected `cefr`/`gender`/`mock` — we deliberately do NOT route through
///    `Requests.post`, which would add those and 422.
class DosageSignalsRepo {
  /// A best-effort signal is disposable, so a POST is abandoned after this
  /// window rather than pinning a pending future (and the awaiting isolate)
  /// indefinitely on a stuck or half-open connection. On timeout the future
  /// errors and is swallowed like any other failure.
  static Duration _requestTimeout = const Duration(seconds: 10);

  static Duration get requestTimeout => _requestTimeout;

  /// Test seam: shorten the timeout so its path is exercised without a real
  /// multi-second wait. Production never sets this.
  @visibleForTesting
  static set requestTimeout(Duration value) => _requestTimeout = value;

  /// A single shared client reuses connections across the frequent small posts.
  /// Lazily created so [dispose] can close and release it — an always-final
  /// client could never be shut down, leaking its connection pool for the app's
  /// lifetime.
  static http.Client? _sharedClient;

  static http.Client get _defaultClient => _sharedClient ??= http.Client();

  /// Closes and releases the shared client (best-effort); the next post lazily
  /// recreates it. Wire into app/analytics teardown so no socket is left open.
  static void dispose() {
    try {
      _sharedClient?.close();
    } catch (_) {
      // Closing a best-effort client must itself never throw into a caller.
    }
    _sharedClient = null;
  }

  /// The shared client, for tests to assert [dispose] released it. Never used by
  /// production code, which reads [_defaultClient].
  @visibleForTesting
  static http.Client get debugDefaultClient => _defaultClient;

  /// Whether dosage signals are active. Requires BOTH flags AND a configured
  /// BFF base URL — any of the three missing makes every post a no-op.
  static bool get isEnabled =>
      Environment.analyticsDualWriteEnabled &&
      Environment.dosageSignalsEnabled &&
      Environment.teacherBffApi.isNotEmpty;

  /// Best-effort POST of one or more message-envelope signals. Skips silently
  /// when disabled, when there is no access token, or when every event is
  /// missing its required room/message id.
  static Future<void> postMessageEvents({
    required List<DosageMessageEvent> events,
    required String? accessToken,
    http.Client? client,
  }) async {
    if (!_canPost(accessToken)) return;
    final valid = events
        .where((e) => e.roomId.isNotEmpty && e.msgId.trim().isNotEmpty)
        .toList();
    if (valid.isEmpty) return;
    await _post(
      url: PApiUrls.dosageMessageEvents,
      body: {"events": valid.map((e) => e.toJson()).toList()},
      accessToken: accessToken!,
      client: client,
      signal: "message-events",
      count: valid.length,
    );
  }

  /// Best-effort POST of one or more engagement spans. Skips a span with an
  /// empty device/span id or a non-positive duration (`span_end > span_start`
  /// is a server CHECK).
  static Future<void> postEngagementSpans({
    required List<DosageEngagementSpan> spans,
    required String? accessToken,
    http.Client? client,
  }) async {
    if (!_canPost(accessToken)) return;
    final valid = spans
        .where(
          (s) =>
              s.deviceId.isNotEmpty &&
              s.spanId.isNotEmpty &&
              s.spanEnd.isAfter(s.spanStart),
        )
        .toList();
    if (valid.isEmpty) return;
    await _post(
      url: PApiUrls.dosageEngagementSpans,
      body: {"spans": valid.map((s) => s.toJson()).toList()},
      accessToken: accessToken!,
      client: client,
      signal: "engagement-spans",
      count: valid.length,
    );
  }

  /// Best-effort POST of one or more session outcomes. Skips an outcome missing
  /// its session-room or activity id.
  static Future<void> postSessionOutcomes({
    required List<DosageSessionOutcome> outcomes,
    required String? accessToken,
    http.Client? client,
  }) async {
    if (!_canPost(accessToken)) return;
    final valid = outcomes
        .where((o) => o.sessionRoomId.isNotEmpty && o.activityId.isNotEmpty)
        .toList();
    if (valid.isEmpty) return;
    await _post(
      url: PApiUrls.dosageSessionOutcomes,
      body: {"outcomes": valid.map((o) => o.toJson()).toList()},
      accessToken: accessToken!,
      client: client,
      signal: "session-outcomes",
      count: valid.length,
    );
  }

  /// Shared ship-dark gate + token guard for all three signals.
  static bool _canPost(String? accessToken) =>
      isEnabled && accessToken != null && accessToken.isNotEmpty;

  /// Shared best-effort POST: fires the request and swallows every failure. The
  /// endpoints are best-effort (202 on accept); we never inspect the status or
  /// retry — a dropped signal is reconciled by the server-side backfill.
  static Future<void> _post({
    required String url,
    required Map<String, dynamic> body,
    required String accessToken,
    required http.Client? client,
    required String signal,
    required int count,
  }) async {
    try {
      final http.Client httpClient = client ?? _defaultClient;
      await httpClient
          .post(
            Uri.parse(url),
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
              "Authorization": "Bearer $accessToken",
            },
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
    } catch (err, s) {
      ErrorHandler.logError(
        e: err,
        s: s,
        level: SentryLevel.warning,
        m: "Best-effort dosage signal POST failed (swallowed)",
        data: {"signal": signal, "count": count},
      );
    }
  }
}
