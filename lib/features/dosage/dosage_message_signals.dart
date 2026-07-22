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

  /// Ensures the dosage env flags are loaded in this isolate before an emit.
  /// dotenv is PER-ISOLATE, so the notification background isolate — which boots
  /// a bare client without loading `.env` — would otherwise read the flags as
  /// unloaded and no-op every emit. Idempotent (no-op once loaded, e.g. in the
  /// main isolate) and best-effort: a load failure just leaves the emit a no-op,
  /// never breaks the notification reply.
  static Future<void> ensureDosageEnvLoaded() async {
    try {
      if (dotenv.isInitialized) return;
      await envLoader();
    } catch (_) {}
  }

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
  }) {
    // Best-effort BOUNDARY: nothing in the dosage emit — including the
    // synchronous envelope build and the engagement tick — may ever escape into
    // the caller's send/save flow. The whole body is guarded and swallowed.
    try {
      // An edit is a Matrix replacement event with a NEW event id but the SAME
      // learner turn. Emitting for it would add a second message envelope and a
      // second engagement tick for one turn, so a send that targets an edit
      // ([editEventId] set) counts nothing here.
      if (editEventId != null) return;

      // The server rejects placeholder ids, so an unresolved send counts nothing
      // — neither the envelope nor the engagement tick. Matches the repo's
      // blank-id guard (trim) so a whitespace-only id records nothing either.
      if (msgEventId == null || msgEventId.trim().isEmpty) return;

      unawaited(
        DosageSignalsRepo.postMessageEvents(
          events: [
            DosageMessageEvent.fromSentMessage(
              roomId: roomId,
              msgId: msgEventId,
              ts: ts ?? DateTime.now(),
              body: body,
              tokenCount: tokenCount,
              langCode: langCode,
            ),
          ],
          accessToken: accessToken,
          client: client,
        ).catchError((_) {}),
      );

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
      ErrorHandler.logError(
        e: e,
        s: s,
        level: SentryLevel.warning,
        m: "Best-effort dosage emit failed (swallowed)",
        data: {"roomId": roomId},
      );
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
  }
}
