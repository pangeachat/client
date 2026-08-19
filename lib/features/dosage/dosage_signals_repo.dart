import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/dosage/dosage_audio_coverage.dart';
import 'package:fluffychat/features/dosage/dosage_audio_event.dart';
import 'package:fluffychat/features/dosage/dosage_engagement_span.dart';
import 'package:fluffychat/features/dosage/dosage_message_event.dart';
import 'package:fluffychat/features/dosage/dosage_session_outcome.dart';
import 'package:fluffychat/features/dosage/dosage_voice_message.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// The outcome of one audio-signals POST.
///
/// A bool would say only whether to retry. The buffer needs one thing more: the
/// route answers 202 for any well-formed batch EVEN WHEN ITS WRITE FAILED, so
/// "the server took the body" is not "the server has the rows" — and a client
/// that extends a coverage period has to know the difference, or it will lengthen
/// a row the server never banked and cover an interval whose events went down
/// with the failed write.
///
/// [coverageWritten] is the server's own count of coverage rows it actually
/// wrote, which it reports precisely so a client can tell a real write from a
/// no-op. The store writes a batch's playbacks and its coverage in ONE
/// transaction, so a count above zero is proof that transaction committed.
class DosageAudioPostResult {
  const DosageAudioPostResult({
    required this.delivered,
    required this.coverageWritten,
  });

  /// The server took the body (2xx). False means keep the batch and retry.
  final bool delivered;

  /// Coverage rows the server reports writing, or null when the response carried
  /// no readable count. Null is treated as "not acknowledged" by the buffer, so
  /// an unreadable response costs an extra coverage row rather than a false one.
  final int? coverageWritten;

  static const DosageAudioPostResult undelivered = DosageAudioPostResult(
    delivered: false,
    coverageWritten: null,
  );
}

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

  /// Creates the HTTP client for a single best-effort POST. Production returns a
  /// FRESH client per request, for two reasons a shared global client can't
  /// give: a timeout can [http.Client.close] it to abort the in-flight socket
  /// (true cancellation, not just a stopped wait), and each request owns its
  /// client — so one request's (or one account's) teardown never closes a client
  /// another is still using, and no pool is left open. Overridable in tests to
  /// inject a spy.
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  /// Whether dosage signals are active. Requires BOTH flags AND a configured
  /// BFF base URL — any of the three missing makes every post a no-op.
  ///
  /// Reading the flags can throw before Environment/dotenv is initialized — e.g.
  /// in the notification background isolate, which boots a bare client without
  /// loading the env. If the gate can't even be read the feature is off, and
  /// this must never throw into a (fire-and-forget) caller, so an unreadable
  /// environment resolves to disabled rather than an exception.
  static bool get isEnabled {
    try {
      return Environment.analyticsDualWriteEnabled &&
          Environment.dosageSignalsEnabled &&
          Environment.teacherBffApi.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Whether client-reported voice-message durations may be put on the wire.
  ///
  /// [isEnabled] PLUS the dedicated capability flag, and the AND is the whole
  /// point. The `voice_messages` field is the ONE part of the audio-signals body
  /// an older server cannot tolerate: its `extra="forbid"` ingest 422s an unknown
  /// key and takes the sibling playback + coverage lanes in the same body down
  /// with it. Those lanes are already live, so the field may reach a server ONLY
  /// once a deployer has confirmed it ships #150 and flips this flag. Reading it
  /// through one getter means the buffer (which stops RECORDING) and
  /// [postAudioSignals] (which stops SENDING) can never disagree about whether the
  /// field is safe. Resolves to false — never throws — if the env is unreadable,
  /// for the same reason [isEnabled] does.
  static bool get voiceMessagesEnabled {
    try {
      return isEnabled && Environment.dosageVoiceMessagesEnabled;
    } catch (_) {
      return false;
    }
  }

  /// The server's `MAX_BATCH`: the most items (playbacks + coverage + voice
  /// messages, counted TOGETHER) one audio-signals body may carry before the
  /// route 413s it and loses the whole period. Mirrors admin-dash-api's
  /// `MAX_BATCH`; [DosageAudioBuffer.maxItemsPerBatch] is the buffer's own copy
  /// of the same server contract (both reference the server, not each other, to
  /// avoid a circular import). The wire builder uses it to bound the VOICE
  /// contribution it adds; the events+coverage aggregate is the buffer's
  /// invariant, which the wire cannot trim without breaking event↔coverage
  /// co-travel (see [postAudioSignals]).
  static const int _maxBatchItems = 200;

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

  /// As [postMessageEvents], but reports whether the server took the body.
  ///
  /// Used ONLY by the voice send. A voice message's envelope is the only
  /// evidence the server ever gets that the message exists — nothing enumerates
  /// a room's timeline — so `voice_send` coverage may only be declared for a
  /// period whose envelopes we can vouch for. Every other caller keeps the
  /// fire-and-forget path above, unchanged.
  ///
  /// Returns false when there was nothing to post, so a caller cannot mistake
  /// "no envelope" for "envelope delivered".
  static Future<bool> postMessageEventsForDelivery({
    required List<DosageMessageEvent> events,
    required String? accessToken,
    http.Client? client,
  }) async {
    if (!_canPost(accessToken)) return false;
    final valid = events
        .where((e) => e.roomId.isNotEmpty && e.msgId.trim().isNotEmpty)
        .toList();
    if (valid.isEmpty) return false;
    return _postForDelivery(
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

  /// Best-effort POST of one period's audio playback signals TOGETHER WITH that
  /// period's coverage declarations, in one body so the server can persist both
  /// in one transaction.
  ///
  /// Unlike the other three signals this one REPORTS ITS OUTCOME, because
  /// listening is the one signal with no Matrix artefact behind it: a lost POST
  /// is an observation gone forever, so [DosageAudioBuffer] has to know whether
  /// to keep the batch. Returns true only on a 2xx. A 404 (the route not
  /// deployed yet, or its flag off) is false — undelivered, not an error — so
  /// the batch is retried rather than dropped.
  ///
  /// A batch with no events AND no coverage says nothing and is not sent; a
  /// batch with only coverage IS sent, because "the instrument was running and
  /// heard nothing" is exactly the observation that turns a null into an honest
  /// zero.
  static Future<DosageAudioPostResult> postAudioSignals({
    required List<DosageAudioEvent> events,
    required List<DosageAudioCoverage> coverage,
    List<DosageVoiceMessage> voiceMessages = const [],
    required String? accessToken,
    http.Client? client,
  }) async {
    if (!_canPost(accessToken)) return DosageAudioPostResult.undelivered;
    final validEvents = events
        .where((e) => e.hasWellFormedRoom && e.elapsedMs > 0)
        .toList();
    final validCoverage = coverage.where((c) => c.isValid).toList();
    // THE load-bearing old-server gate. This is the single place `voice_messages`
    // enters the wire, and gating it on [voiceMessagesEnabled] makes the ONE
    // safety-critical direction true by construction: the field is on the wire
    // ONLY IF the flag is on — equivalently, flag off (the default, and the whole
    // steady state until #150 is deployed) NEVER sends the key, leaving a body
    // byte-identical to today's that every already-live server accepts. The
    // converse does NOT hold: flag on merely PERMITS the field; whether it then
    // actually appears also needs valid, non-empty voice rows with cap room (see
    // the `if (validVoiceMessages.isNotEmpty)` on the body below). `events` and
    // `coverage` keep posting regardless. Tying flag-on to "every target server
    // has #150" is an OPERATIONAL contract (enable the flag only after #150
    // deploys), not something the code proves — the 422 retry below is the net for
    // when that contract slips. Invalid rows (out-of-bound duration, blank id) are
    // dropped per-row so one bad row never 422s the batch.
    //
    // The wire cap trims VOICE so this change can never turn a within-budget body
    // into a 413: it holds `voice <= _maxBatchItems - events - coverage`. The
    // events+coverage aggregate stays the BUFFER's invariant (it seals at most 186
    // observations + 14 coverage = 200) and the wire deliberately does NOT re-own
    // it: trimming an event while keeping the coverage that declared its period
    // would serve an undercount as a confident total, the very defect co-travel
    // exists to avoid. So voice is the only list safe to trim here, and it is
    // dropped first precisely so a trim can never touch the already-live lanes.
    final int voiceRoom =
        _maxBatchItems - validEvents.length - validCoverage.length;
    final validVoiceMessages = voiceMessagesEnabled
        ? voiceMessages
              .where((v) => v.isValid)
              .take(voiceRoom < 0 ? 0 : voiceRoom)
              .toList()
        : const <DosageVoiceMessage>[];
    if (validEvents.isEmpty &&
        validCoverage.isEmpty &&
        validVoiceMessages.isEmpty) {
      return DosageAudioPostResult.undelivered;
    }
    final Map<String, dynamic> baseBody = {
      "events": validEvents.map((e) => e.toJson()).toList(),
      "coverage": validCoverage.map((c) => c.toJson()).toList(),
    };
    http.Response? response = await _sendForDelivery(
      url: PApiUrls.dosageAudioSignals,
      body: validVoiceMessages.isEmpty
          ? baseBody
          : {
              ...baseBody,
              "voice_messages": validVoiceMessages
                  .map((v) => v.toJson())
                  .toList(),
            },
      accessToken: accessToken!,
      client: client,
      signal: "audio-signals",
      count:
          validEvents.length + validCoverage.length + validVoiceMessages.length,
    );
    // Old-server safety net for the already-live lanes. A server that predates
    // the `voice_messages` field 422s the unknown key and drops the WHOLE batch,
    // listening included. The capability flag makes that unreachable in correct
    // operation, but if the flag is ever enabled against such a server, retry
    // ONCE with the field stripped so the playback + coverage lanes still land.
    // Only on a 422 (a body-shape rejection), only when we actually sent the
    // field, and only when there is a sibling lane to salvage — never for a
    // 404/5xx, which the buffer's own retry handles. This is belt-and-suspenders
    // on the siblings, never the primary gate, which stays the flag above.
    if (validVoiceMessages.isNotEmpty &&
        (validEvents.isNotEmpty || validCoverage.isNotEmpty) &&
        response != null &&
        response.statusCode == 422) {
      response = await _sendForDelivery(
        url: PApiUrls.dosageAudioSignals,
        body: baseBody,
        accessToken: accessToken,
        client: client,
        signal: "audio-signals",
        count: validEvents.length + validCoverage.length,
      );
    }
    if (response == null || !_isDelivered(response.statusCode)) {
      return DosageAudioPostResult.undelivered;
    }
    return DosageAudioPostResult(
      delivered: true,
      coverageWritten: _coverageWritten(response),
    );
  }

  /// The coverage-row count out of an accepted response, or null when the body
  /// did not carry a readable one.
  ///
  /// Defensive to the point of paranoia because this runs on a best-effort path
  /// that must never throw: an unparseable body, a non-map body, a missing or
  /// non-numeric field all resolve to null, which the buffer reads as "not
  /// acknowledged" and answers by opening a fresh period rather than extending.
  /// Every failure here costs one extra coverage row; none of them can produce a
  /// declaration for an interval the server does not hold.
  static int? _coverageWritten(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final value = decoded["coverage"];
      return value is num ? value.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  /// Shared ship-dark gate + token guard for every signal.
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
    // A caller-injected client is the caller's to manage; otherwise create a
    // per-request client we own and MUST close in `finally`. On the timeout path
    // that close tears down the still-in-flight socket (true cancellation); on
    // success it releases the connection.
    final http.Client httpClient = client ?? clientFactory();
    final bool ownsClient = client == null;
    try {
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
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  /// As [_post], but reports whether the server actually took the body. Only a
  /// 2xx counts as delivered; anything else — a 404 while the route is
  /// undeployed, a 5xx, a timeout, an offline socket — is undelivered and the
  /// caller retries.
  static Future<bool> _postForDelivery({
    required String url,
    required Map<String, dynamic> body,
    required String accessToken,
    required http.Client? client,
    required String signal,
    required int count,
  }) async {
    final http.Response? response = await _sendForDelivery(
      url: url,
      body: body,
      accessToken: accessToken,
      client: client,
      signal: signal,
      count: count,
    );
    return response != null && _isDelivered(response.statusCode);
  }

  static bool _isDelivered(int statusCode) =>
      statusCode >= 200 && statusCode < 300;

  /// One best-effort POST, returning the RESPONSE so a caller that needs more
  /// than "did it land" can read the body. Null means the request never
  /// completed — a timeout, an offline socket — which is undelivered.
  ///
  /// A non-2xx status is NOT logged. It is the expected steady state until the
  /// server ships this route, and reporting it would put one warning per
  /// heartbeat per user into Sentry for a condition that is by design. Transport
  /// exceptions are logged exactly as the other signals log them.
  static Future<http.Response?> _sendForDelivery({
    required String url,
    required Map<String, dynamic> body,
    required String accessToken,
    required http.Client? client,
    required String signal,
    required int count,
  }) async {
    final http.Client httpClient = client ?? clientFactory();
    final bool ownsClient = client == null;
    try {
      return await httpClient
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
      return null;
    } finally {
      if (ownsClient) httpClient.close();
    }
  }
}
