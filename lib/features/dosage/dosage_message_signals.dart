import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/dosage/dosage_engagement_tracker.dart';
import 'package:fluffychat/features/dosage/dosage_message_event.dart';
import 'package:fluffychat/features/dosage/dosage_signals_repo.dart';

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

  static void emitForSentMessage({
    required String roomId,
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
    // An edit is a Matrix replacement event with a NEW event id but the SAME
    // learner turn. Emitting for it would add a second message envelope and a
    // second engagement tick for one turn, so a send that targets an edit
    // ([editEventId] set) counts nothing here.
    if (editEventId != null) return;

    // The server rejects placeholder ids, so an unresolved send counts nothing —
    // neither the envelope nor the engagement tick. Matches the repo's blank-id
    // guard (trim) so a whitespace-only id records nothing either.
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

    // The tracker guards an empty device id; passing it through keeps the
    // engagement decision in one place.
    (tracker ?? DosageEngagementTracker.instance).recordActivity(
      deviceId: deviceId ?? "",
      accessToken: accessToken,
    );
  }

  /// Whether a successful resend ([Event.sendAgain]) is a learner text turn that
  /// should emit an envelope. Only a text resend counts — a file/media resend
  /// carries no learner text. An edit resend is filtered separately by
  /// [emitForSentMessage]'s edit guard.
  static bool isResendableLearnerText(String messageType) =>
      messageType == MessageTypes.Text;

  /// The learner's own text for a message, with any rich-reply fallback removed.
  /// A reply's `body` is prefixed with the referenced message's quoted
  /// `> <@user> …` lines; counting those would inflate the envelope with text
  /// the learner did not write (the composer counts only the typed text).
  /// Mirrors the SDK's `hideReply` crop.
  static String strippedLearnerText(String body) => body.replaceFirst(
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
      deviceId: event.room.client.deviceID,
      accessToken: event.room.client.accessToken,
      msgEventId: resolvedId,
      body: strippedLearnerText(event.body),
      editEventId: event.relationshipType == RelationshipTypes.edit
          ? event.eventId
          : null,
      client: client,
      tracker: tracker,
    );
  }
}
