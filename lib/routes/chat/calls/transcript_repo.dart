import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

/// One page of related events, as the server returns them.
///
/// Injected rather than reached for, so the paging and exhaustion rules below
/// can be tested without a homeserver — they are the part most likely to be
/// wrong, and the hardest to provoke against a real server.
typedef RelationsFetcher =
    Future<({List<MatrixEvent> chunk, String? nextBatch})> Function({
      required String roomId,
      required String eventId,
      required String relType,
      String? from,
    });

/// What a reader will spend on one call, whatever the room contains.
///
/// A single room member can write as many related events as they like, so the
/// page and event ceilings are not tuning knobs — they are the reason opening a
/// transcript cannot be made to hang. Hitting either yields an INCOMPLETE
/// result, never an absent one: stopping early is our doing, and reporting it
/// as "they said nothing" would be a lie about another person.
const kMaxRelationPages = 10;
const kMaxRelationEvents = 200;

/// Reads both halves of one call.
///
/// [expectedSenders] is who took part, so a participant who wrote nothing is
/// reported absent rather than quietly omitted.
Future<CallTranscript> fetchCallTranscript({
  required RelationsFetcher fetch,
  required String roomId,
  required String callKey,
  required List<String> expectedSenders,
  int maxPages = kMaxRelationPages,
  int maxEvents = kMaxRelationEvents,
}) async {
  final candidates = <TranscriptCandidate>[];
  var exhausted = false;
  var cappedMidPage = false;
  var seen = 0;
  String? from;

  for (var page = 0; page < maxPages; page++) {
    final result = await fetch(
      roomId: roomId,
      eventId: callKey,
      relType: CallTranscriptContent.relType,
      from: from,
    );

    for (final event in result.chunk) {
      if (seen >= maxEvents) {
        // The cap was hit part-way through a page. Recorded, because the page
        // itself may have been the last one: seeing `nextBatch == null` below
        // would otherwise call this read exhausted and let a half we never
        // looked at be reported ABSENT -- the exact conflation this design
        // exists to prevent, arrived at from the one direction not yet covered.
        cappedMidPage = true;
        break;
      }
      seen++;

      // The relation type is what was queried, but the EVENT type still has to
      // match: a relation of this type carrying some other event type is not a
      // transcript, and parsing it as one would invent content.
      if (event.type != CallTranscriptContent.relType) continue;

      final content = CallTranscriptContent.fromJson(event.content);
      if (content == null) continue;

      // A half whose content names a different call is not this call's, even
      // though the server returned it under this anchor.
      if (content.callKey != callKey) continue;

      candidates.add(
        TranscriptCandidate(
          senderId: event.senderId,
          originServerTs: event.originServerTs.millisecondsSinceEpoch,
          segments: content.segments,
          accounting: content.accounting,
        ),
      );
    }

    from = result.nextBatch;

    // Exhausted means the SERVER said there is no more. Only then may a
    // missing half be called absent rather than unread.
    if (from == null) {
      // Only a read that examined everything the server offered may claim to
      // have seen everything.
      exhausted = !cappedMidPage;
      break;
    }
    if (seen >= maxEvents) break;
  }

  return assembleTranscript(
    candidates: candidates,
    expectedSenders: expectedSenders,
    exhausted: exhausted,
  );
}

/// The [RelationsFetcher] that talks to a real homeserver.
RelationsFetcher relationsFetcherFor(Client client) =>
    ({
      required String roomId,
      required String eventId,
      required String relType,
      String? from,
    }) async {
      final response = await client.getRelatingEventsWithRelType(
        roomId,
        eventId,
        relType,
        from: from,
      );
      return (chunk: response.chunk, nextBatch: response.nextBatch);
    };
