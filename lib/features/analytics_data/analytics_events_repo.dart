import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Best-effort dual-write of a student's just-written construct uses to the
/// teacher-BFF (admin-dash-api) `POST /api/internal/analytics-events`.
///
/// This is a side-channel to the canonical Matrix write, NOT a replacement:
/// the app still writes `pangea.construct` events to the student's analytics
/// room as before. After a batch is written to Matrix and its real event id is
/// known, we ALSO POST those raw uses here so the server's durable
/// `analytics_event_log` fills in real time (send-then-POST — the server rejects
/// a blank/placeholder id, so the id MUST be the resolved Matrix event id).
///
/// Guarantees:
///  * **Non-blocking / never throws.** Every failure path is swallowed and, at
///    most, logged. A dual-write failure must never surface to the user or break
///    the normal analytics/Matrix flow. Callers can fire-and-forget.
///  * **Ships dark.** A no-op unless BOTH [Environment.analyticsDualWriteEnabled]
///    is set AND [Environment.teacherBffApi] is configured. Either being unset
///    means the POST is skipped entirely.
///  * **Contract-exact body.** The wire body is exactly
///    `{ analytics_room_id, events: [{ matrix_event_id, uses: [<raw use>, ...] }] }`
///    with each `uses` entry the verbatim [OneConstructUse.toJson] dict — the
///    same object written to Matrix. We deliberately do NOT route through
///    `Requests.post`, which injects `cefr`/`gender`/`mock` into the top-level
///    body; the endpoint is `extra="forbid"`, so an injected key would 422.
///    `use_index` is implicit: it is each use's 0-based position in `uses[]`,
///    which the server enumerates, matching the server backfill's `event_uid`.
class AnalyticsEventsRepo {
  /// The shared client used when no override is injected. A single client
  /// reuses connections across the frequent small analytics posts.
  static final http.Client _defaultClient = http.Client();

  /// Whether the dual-write is active. Requires the flag AND a configured BFF
  /// base URL — either missing makes every post a no-op.
  static bool get isEnabled =>
      Environment.analyticsDualWriteEnabled &&
      Environment.teacherBffApi.isNotEmpty;

  /// Best-effort POST of one Matrix `pangea.construct` batch's uses.
  ///
  /// [analyticsRoomId] is the student's analytics room; [matrixEventId] is the
  /// REAL event id the batch was sent under (send-then-POST); [uses] are the
  /// exact uses written in that event, in order. Returns silently and never
  /// throws — a failure is logged as a warning at most.
  ///
  /// [accessToken] is the student's Matrix access token (bearer). [client] is an
  /// optional injection point for tests.
  static Future<void> postConstructUses({
    required String analyticsRoomId,
    required String matrixEventId,
    required List<OneConstructUse> uses,
    required String? accessToken,
    http.Client? client,
  }) async {
    // Ship-dark gate + cheap validity guards. Never a no-op-failure; just skip.
    if (!isEnabled) return;
    if (accessToken == null || accessToken.isEmpty) return;
    if (analyticsRoomId.isEmpty) return;
    // Send-then-POST: a blank/placeholder id is rejected by the server (422),
    // so never post one — this mirrors the server's own guard.
    if (matrixEventId.trim().isEmpty) return;
    if (uses.isEmpty) return;

    try {
      // Built inside the best-effort try so even serialization (`toJson` /
      // `jsonEncode` of a near-max chunk) can never throw out of this method —
      // the repo's "never throws" contract holds however it is called.
      final Map<String, dynamic> body = {
        "analytics_room_id": analyticsRoomId,
        "events": [
          {
            "matrix_event_id": matrixEventId,
            // Verbatim raw uses — same dicts written to Matrix. Order is the
            // authoritative use_index the server enumerates from uses[].
            "uses": uses.map((use) => use.toJson()).toList(),
          },
        ],
      };

      final http.Client httpClient = client ?? _defaultClient;
      await httpClient.post(
        Uri.parse(PApiUrls.analyticsEvents),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "Authorization": "Bearer $accessToken",
        },
        body: jsonEncode(body),
      );
      // The endpoint is best-effort (always 202); we do not inspect the status
      // or retry here. A dropped write is reconciled by the server-side backfill,
      // so there is nothing to surface on a non-2xx.
    } catch (err, s) {
      // Swallow every error — a dual-write failure must never break the normal
      // analytics/Matrix flow. Log as a warning (not an error) since the data is
      // already durably in Matrix and the server backfill is the safety net.
      ErrorHandler.logError(
        e: err,
        s: s,
        level: SentryLevel.warning,
        m: "Best-effort analytics dual-write POST failed (swallowed)",
        data: {
          "analytics_room_id": analyticsRoomId,
          "matrix_event_id": matrixEventId,
          "use_count": uses.length,
        },
      );
    }
  }
}
