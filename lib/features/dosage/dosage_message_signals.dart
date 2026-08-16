import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/dosage/dosage_engagement_tracker.dart';
import 'package:fluffychat/features/dosage/dosage_message_event.dart';
import 'package:fluffychat/features/dosage/dosage_signals_repo.dart';
import 'package:fluffychat/pangea/common/config/env_loader.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// The single place the "a learner sent a chat message" dosage signals are
/// emitted: the message envelope (for EVERY sent message) plus a tick of
/// engagement activity. Every learner-text send path calls this so the logic
/// lives here, not copy-pasted per call site.
///
/// Fire-and-forget and never throws: it hands off to [DosageSignalsRepo] and
/// [DosageEngagementTracker] (both best-effort, no-op unless the dosage flags
/// are enabled) without awaiting. Send-then-POST — pass the RESOLVED Matrix
/// event id; a null/blank id means the send didn't land, so nothing counts.
class DosageMessageSignals {
  DosageMessageSignals._();

  /// Loads the dosage env (`.env`) into THIS isolate. Overridable in tests.
  @visibleForTesting
  static Future<void> Function() envLoader = EnvLoader.load;

  /// The single in-flight env load for this isolate, so concurrent first-emits
  /// coalesce onto ONE load instead of racing N parallel `.env` reads. Cleared
  /// once the load settles, so a failed load can be retried by a later emit.
  static Future<void>? _envLoad;

  /// Ensures the dosage env flags are loaded in this isolate before an emit.
  /// dotenv is PER-ISOLATE, so the notification background isolate — which boots
  /// a bare client without loading `.env` — would otherwise read the flags as
  /// unloaded and no-op every emit. Idempotent (no-op once loaded, e.g. in the
  /// main isolate), single-flight (coalesced), and best-effort: the load is
  /// TIME-BOXED and swallowed so a slow or failing `.env` read can never hang or
  /// throw into the caller (a notification reply) — it just leaves the emit a
  /// no-op.
  static Future<void> ensureDosageEnvLoaded() {
    if (dotenv.isInitialized) return Future.value();
    // Single-flight on the RAW loader: coalesce concurrent callers onto ONE
    // underlying load and clear the latch only when that raw load actually
    // SETTLES. The per-caller timeout is applied as a separate VIEW below, never
    // to the latched future itself — otherwise a timed-out view would clear the
    // latch while the real load is still running and let a second caller kick
    // off a duplicate concurrent load.
    final raw = _envLoad ??= () async {
      try {
        await envLoader();
      } catch (_) {
        // Best-effort: a failed load just leaves the flags unloaded.
      } finally {
        _envLoad = null;
      }
    }();
    // Each caller awaits its OWN 5s-bounded view of the shared load, so a slow
    // `.env` read never hangs a caller (e.g. a notification reply) while still
    // running exactly one real load.
    return raw.timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  /// Clears the single-flight env latch (tests only).
  @visibleForTesting
  static void debugResetEnvLoad() => _envLoad = null;

  static void emitForSentMessage({
    required String roomId,
    required String? userId,
    required String? deviceId,
    required String? accessToken,
    required String? msgEventId,
    required String body,
    int? tokenCount,
    String? langCode,
    String? editEventId,
    DateTime? ts,
    http.Client? client,
    DosageEngagementTracker? tracker,
    void Function(bool delivered)? onEnvelopeSettled,
  }) {
    // Called on EVERY exit, exactly once, whenever a caller supplied it. A
    // caller that tracks unconfirmed envelopes (the voice send, whose coverage
    // depends on them) would otherwise be left with one outstanding forever on
    // the guard paths below, and withhold its counter permanently.
    var settled = false;
    void settle({required bool delivered}) {
      if (settled) return;
      settled = true;
      try {
        onEnvelopeSettled?.call(delivered);
      } catch (_) {}
    }

    // Best-effort BOUNDARY: nothing in the dosage emit — including the
    // synchronous envelope build and the engagement tick — may ever escape into
    // the caller's send/save flow. The whole body is guarded and swallowed.
    try {
      // An edit is a Matrix replacement event with a NEW event id but the SAME
      // learner turn. Emitting for it would add a second message envelope and a
      // second engagement tick for one turn, so a send that targets an edit
      // ([editEventId] set) counts nothing here.
      if (editEventId != null) {
        // Nothing was sent, so nothing is outstanding — not a loss.
        settle(delivered: true);
        return;
      }

      // The server rejects placeholder ids, so an unresolved send counts nothing
      // — neither the envelope nor the engagement tick. Matches the repo's
      // blank-id guard (trim) so a whitespace-only id records nothing either.
      if (msgEventId == null || msgEventId.trim().isEmpty) {
        // The send itself did not land, so there is no message for the server to
        // be missing. Nothing outstanding.
        settle(delivered: true);
        return;
      }

      final events = [
        DosageMessageEvent.fromSentMessage(
          roomId: roomId,
          msgId: msgEventId,
          ts: ts ?? DateTime.now(),
          body: body,
          tokenCount: tokenCount,
          langCode: langCode,
        ),
      ];

      if (onEnvelopeSettled == null) {
        // The unchanged path every text send takes: fire, forget, never inspect
        // the status.
        unawaited(
          DosageSignalsRepo.postMessageEvents(
            events: events,
            accessToken: accessToken,
            client: client,
          ).catchError((_) {}),
        );
      } else {
        // Still fire-and-forget for the CALLER — nothing below is awaited — but
        // the outcome is reported so a coverage declaration can depend on it.
        unawaited(
          DosageSignalsRepo.postMessageEventsForDelivery(
            events: events,
            accessToken: accessToken,
            client: client,
          ).then(
            (delivered) => settle(delivered: delivered),
            onError: (_) => settle(delivered: false),
          ),
        );
      }

      // Resolve the ACCOUNT's tracker (per-account, so accounts never merge);
      // an unknown account (empty userId) records no engagement tick. The
      // tracker itself guards an empty device id.
      final t = tracker ?? DosageEngagementTracker.forAccount(userId ?? "");
      t?.recordActivity(
        userId: userId ?? "",
        deviceId: deviceId ?? "",
        accessToken: accessToken,
      );
    } catch (e, s) {
      // A throw somewhere in the emit means we cannot claim the envelope was
      // sent. Reporting it as undelivered withholds the period rather than
      // licensing a zero we did not observe.
      settle(delivered: false);
      // Even the error report is best-effort. ErrorHandler.logError is async, so
      // a Sentry failure (e.g. uninitialised in a bare background isolate)
      // surfaces as a REJECTED future, which a synchronous try/catch can't
      // observe — attach catchError and detach it so it can never reach the
      // send flow as an unhandled error.
      unawaited(
        ErrorHandler.logError(
          e: e,
          s: s,
          level: SentryLevel.warning,
          m: "Best-effort dosage emit failed (swallowed)",
          data: {"roomId": roomId},
        ).catchError((_) {}),
      );
    }
  }

  /// AWAITABLE, bounded, never-throw emit of JUST the message envelope for a
  /// notification reply. The notification handler AWAITS this so a short-lived
  /// background isolate — which tears down its client right after the reply —
  /// doesn't finish before the POST lands (a fire-and-forget emit there is
  /// silently dropped when the isolate ends).
  ///
  /// Envelope only, no engagement tick: the background isolate has its own
  /// (isolate-local) tracker registry with no lifecycle to flush a span, and a
  /// single reply's engagement is negligible against the message envelope. The
  /// POST is bounded by the repo's per-request timeout and fully swallowed, so
  /// this never blocks or breaks the reply.
  static Future<void> emitReplyEnvelope({
    required String roomId,
    required String? accessToken,
    required String? msgEventId,
    required String body,
    http.Client? client,
  }) async {
    try {
      // A blank/placeholder id means the reply send didn't resolve; count
      // nothing (mirrors [emitForSentMessage]'s id guard).
      if (msgEventId == null || msgEventId.trim().isEmpty) return;
      await DosageSignalsRepo.postMessageEvents(
        events: [
          DosageMessageEvent.fromSentMessage(
            roomId: roomId,
            msgId: msgEventId,
            ts: DateTime.now(),
            body: body,
          ),
        ],
        accessToken: accessToken,
        client: client,
      );
    } catch (_) {
      // Best-effort — never block or break the notification reply.
    }
  }

  /// Whether a successful resend ([Event.sendAgain]) is a learner text turn that
  /// should emit an envelope. Only a text resend counts — a file/media resend
  /// carries no learner text. An edit resend is filtered separately by
  /// [emitForSentMessage]'s edit guard.
  static bool isResendableLearnerText(String messageType) =>
      messageType == MessageTypes.Text;

  /// The learner's own text for a message [content]. Only strips the rich-reply
  /// quoted fallback when the message actually IS a reply — keyed on the reply
  /// RELATION (`m.relates_to.m.in_reply_to`), NOT on the body shape. So ordinary
  /// learner text that merely begins with a `> <@…>`-looking line is counted in
  /// full, and a forward (whose `m.relates_to` was removed) is never stripped.
  static String learnerText(Map<String, dynamic> content) {
    final body = content['body'];
    final bodyStr = body is String ? body : '';
    final relatesTo = content['m.relates_to'];
    final isReply = relatesTo is Map && relatesTo['m.in_reply_to'] != null;
    return isReply ? _stripReplyFallback(bodyStr) : bodyStr;
  }

  /// Crops the leading `> <@user> …` reply fallback block. Mirrors the SDK's
  /// `hideReply` crop; only ever applied to a genuine reply (see [learnerText]).
  static String _stripReplyFallback(String body) => body.replaceFirst(
    RegExp(r'^>( \*)? <[^>]+>[^\n\r]+\r?\n(> [^\n]*\r?\n)*\r?\n'),
    '',
  );

  /// Emits the learner-message signals for a resend of a failed send
  /// ([Event.sendAgain], which resends then resolves the new event id).
  /// Fire-and-forget; returns the future so tests can await it. It uses the
  /// RESOLVED (post-resend) event id, counts only the learner's own text (reply
  /// fallback stripped), and skips a file/media resend and an edit replacement —
  /// neither is a new learner turn.
  static Future<void> emitForResend(
    Event event, {
    http.Client? client,
    DosageEngagementTracker? tracker,
  }) async {
    final String? resolvedId;
    try {
      resolvedId = await event.sendAgain();
    } catch (_) {
      // The resend itself failed (e.g. a file whose bytes are no longer cached
      // makes sendAgain throw); nothing to emit, and this best-effort path must
      // never throw into its fire-and-forget caller.
      return;
    }
    // The resend already succeeded above; the dosage emit is pure telemetry and
    // must never disturb it, so the whole emit (argument reads included) is
    // guarded and swallowed.
    try {
      if (!isResendableLearnerText(event.messageType)) return;
      emitForSentMessage(
        roomId: event.room.id,
        userId: event.room.client.userID,
        deviceId: event.room.client.deviceID,
        accessToken: event.room.client.accessToken,
        msgEventId: resolvedId,
        body: learnerText(event.content),
        editEventId: event.relationshipType == RelationshipTypes.edit
            ? event.eventId
            : null,
        client: client,
        tracker: tracker,
      );
    } catch (_) {}
  }

  /// Emits the message envelope for a FORWARDED message's content (a
  /// `ContentShareItem`): it sends [content] into [room], then — for text only —
  /// emits under the RESOLVED event id, counting only the learner's own text.
  /// Non-text forwards send but emit nothing. Fire-and-forget; returns the
  /// future so tests can await it, and never throws.
  static Future<void> emitForForwardedContent(
    Room room,
    Map<String, dynamic> content, {
    http.Client? client,
    DosageEngagementTracker? tracker,
  }) async {
    final String? resolvedId;
    try {
      resolvedId = await room.sendEvent(content);
    } catch (_) {
      return;
    }
    // The forward already sent above; the dosage emit is pure telemetry and must
    // never disturb it, so the whole emit is guarded and swallowed.
    try {
      if (content['msgtype'] != MessageTypes.Text) return;
      emitForSentMessage(
        roomId: room.id,
        userId: room.client.userID,
        deviceId: room.client.deviceID,
        accessToken: room.client.accessToken,
        msgEventId: resolvedId,
        body: learnerText(content),
        client: client,
        tracker: tracker,
      );
    } catch (_) {}
  }
}
