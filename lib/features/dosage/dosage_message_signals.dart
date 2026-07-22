import 'dart:async';

import 'package:http/http.dart' as http;

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
}
