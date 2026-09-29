import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';

/// One playable recording found for a call: the event that carries it, and
/// who wrote it.
///
/// [CallAudioContent] itself carries no sender -- that lives on the Matrix
/// event, exactly as it does for a transcript half -- so this pairs the two
/// the same way [transcript_view.dart]'s screen already pairs a
/// [TranscriptHalf] with the sender it read it from.
class CallAudioRecording {
  /// The `pangea.call_audio` event's own id. Stable and globally unique, so
  /// it is what the player uses to key "which recording is this instance
  /// playing" -- see `AudioPlayerWidget.eventId`.
  final String eventId;

  final String senderId;

  final DateTime originServerTs;

  final CallAudioContent content;

  const CallAudioRecording({
    required this.eventId,
    required this.senderId,
    required this.originServerTs,
    required this.content,
  });
}

/// Reads every `pangea.call_audio` half saved for one call.
///
/// Mirrors [fetchCallTranscript]'s walk of the relations timeline: paged
/// through the same [RelationsFetcher] seam, capped by the same read
/// ceilings ([kMaxRelationPages], [kMaxRelationEvents]), and tolerant of a
/// malformed or foreign event returned under this call's anchor -- one bad
/// recording must not take the rest of the list down, and nothing here
/// throws on room content, which is untrusted.
///
/// Unlike the transcript, an ABSENT recording is not a state this reader
/// reports on. Recording is a distinct, separately gated capability from
/// transcription, and most calls carry none of these events at all -- so
/// there is no participant list to check a device against, no "absent"
/// half to report, and no caveat to raise when the list comes back empty.
/// The caller shows nothing, which is the true and complete answer; see
/// `CallTranscriptView`, which does exactly that.
///
/// An encrypted room needs no special case here, for the same reason
/// [fetchCallTranscript]'s own doc explains: nothing on the relations path
/// decrypts, so every event comes back typed `m.room.encrypted` and is
/// filtered out below as not-a-recording, which already yields the correct
/// empty answer.
Future<List<CallAudioRecording>> fetchCallAudio({
  required RelationsFetcher fetch,
  required String roomId,
  required String callKey,
  int maxPages = kMaxRelationPages,
  int maxEvents = kMaxRelationEvents,
}) async {
  final recordings = <CallAudioRecording>[];
  var seen = 0;
  String? from;

  for (var page = 0; page < maxPages; page++) {
    final result = await fetch(
      roomId: roomId,
      eventId: callKey,
      relType: CallAudioContent.relType,
      from: from,
    );

    for (final event in result.chunk) {
      if (seen >= maxEvents) break;
      seen++;

      // The relation type is what was queried, but the EVENT type still has
      // to match -- on the same terms `fetchCallTranscript` reads its own
      // relations. A relation of this type carrying some other event type
      // (every event in an encrypted room, for instance, comes back typed
      // `m.room.encrypted`) is not a recording, and parsing it as one would
      // invent content.
      if (event.type != CallAudioContent.relType) continue;

      final content = CallAudioContent.fromJson(event.content);
      if (content == null) {
        // Recorded so a foreign or corrupted half is diagnosable rather than
        // silently vanishing into "this call has no recording". No sender id
        // here, on the same privacy footing `fetchCallTranscript`'s own
        // per-half summary already keeps: the call key is what the report
        // needs, not a durable, cross-call-correlatable Matrix id.
        Logs().w(
          'A pangea.call_audio relation on $callKey could not be parsed; '
          'skipped',
        );
        continue;
      }

      // Returned under this call's anchor but naming a different one -- not
      // this call's recording even though the server filed it here.
      if (content.callKey != callKey) continue;

      recordings.add(
        CallAudioRecording(
          eventId: event.eventId,
          senderId: event.senderId,
          originServerTs: event.originServerTs,
          content: content,
        ),
      );
    }

    from = result.nextBatch;
    if (from == null) break;
    if (seen >= maxEvents) break;
  }

  return recordings;
}

/// One merged, full-call recording found for a call: the
/// `pangea.call_audio_merged` event that carries it, and who posted it.
///
/// [CallAudioMergedContent] itself carries no sender either, for the same
/// reason [CallAudioContent] does not -- see [CallAudioRecording]'s own docs
/// -- so this pairs the two exactly as that record does, one field renamed
/// for the sibling event's content type.
class CallAudioMergedRecording {
  /// The `pangea.call_audio_merged` event's own id.
  final String eventId;

  final String senderId;

  final DateTime originServerTs;

  final CallAudioMergedContent content;

  const CallAudioMergedRecording({
    required this.eventId,
    required this.senderId,
    required this.originServerTs,
    required this.content,
  });
}

/// Reads every `pangea.call_audio_merged` recording posted for one call.
///
/// A straight mirror of [fetchCallAudio] -- same paging seam, same read
/// ceilings, same tolerance of a malformed or foreign event under this call's
/// anchor -- with the relation type and parser swapped for
/// [CallAudioMergedContent]'s own. See that function's own docs for the full
/// reasoning; nothing here differs but which event this reads.
Future<List<CallAudioMergedRecording>> fetchCallAudioMerged({
  required RelationsFetcher fetch,
  required String roomId,
  required String callKey,
  int maxPages = kMaxRelationPages,
  int maxEvents = kMaxRelationEvents,
}) async {
  final recordings = <CallAudioMergedRecording>[];
  var seen = 0;
  String? from;

  for (var page = 0; page < maxPages; page++) {
    final result = await fetch(
      roomId: roomId,
      eventId: callKey,
      relType: CallAudioMergedContent.relType,
      from: from,
    );

    for (final event in result.chunk) {
      if (seen >= maxEvents) break;
      seen++;

      // Same rule as [fetchCallAudio]: the relation type is what was
      // queried, but the EVENT type still has to match, or parsing it as a
      // merged recording would invent content.
      if (event.type != CallAudioMergedContent.relType) continue;

      final content = CallAudioMergedContent.fromJson(event.content);
      if (content == null) {
        // Recorded for the same reason [fetchCallAudio] logs its own skip:
        // so a foreign or corrupted merge is diagnosable rather than
        // silently vanishing into "this call has no merged recording".
        Logs().w(
          'A pangea.call_audio_merged relation on $callKey could not be '
          'parsed; skipped',
        );
        continue;
      }

      // Returned under this call's anchor but naming a different one -- not
      // this call's merge even though the server filed it here.
      if (content.callKey != callKey) continue;

      recordings.add(
        CallAudioMergedRecording(
          eventId: event.eventId,
          senderId: event.senderId,
          originServerTs: event.originServerTs,
          content: content,
        ),
      );
    }

    from = result.nextBatch;
    if (from == null) break;
    if (seen >= maxEvents) break;
  }

  return recordings;
}
