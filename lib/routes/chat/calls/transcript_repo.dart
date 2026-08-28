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
///
/// [encrypted] is whether the room encrypts its events. The relations endpoint
/// returns them as the server holds them, and nothing on that path decrypts:
/// in an encrypted room every half comes back typed `m.room.encrypted` and is
/// filtered out below as not-a-transcript. A read like that has not found
/// nothing -- it has failed to look -- and calling both speakers ABSENT off it
/// would tell each of them the other said nothing. Pangea creates its rooms
/// unencrypted (every `startDirectChat` call site passes `enableEncryption:
/// false`), so this is a guard against a room we did not make, not a live
/// path. It defaults to false so a caller that does not know cannot be made
/// worse off, and the honest answer is INCOMPLETE.
Future<CallTranscript> fetchCallTranscript({
  required RelationsFetcher fetch,
  required String roomId,
  required String callKey,
  required List<String> expectedSenders,

  /// This account, so a diagnostic can say self or peer without naming anyone.
  String? selfId,

  /// Whether [expectedSenders] is an answer or a guess. See
  /// [assembleTranscript]: a guess that comes up short must not be allowed to
  /// discard a real half in silence.
  bool participantsKnown = true,
  bool encrypted = false,
  int maxPages = kMaxRelationPages,
  int maxEvents = kMaxRelationEvents,
}) async {
  final candidates = <TranscriptCandidate>[];

  // Senders whose event we found and could NOT parse.
  //
  // Dropping it silently and moving on let assembly see no half from that
  // sender and, on an exhausted read, report them ABSENT -- "no transcript
  // from them", when the truth is that they wrote one and we could not read
  // it. The event's SENDER survives a content that does not, so this costs
  // one set and closes the last route from a reader failure to a claim about
  // what somebody did.
  final unreadable = <String>{};
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
      if (event.type != CallTranscriptContent.relType) {
        // Recorded, not merely skipped. It is not a transcript and must never
        // be parsed as one -- but something from this sender DID arrive under
        // this call's anchor, and concluding from that that they were silent
        // is the same mistake as concluding it from a content we could not
        // parse. The rule is about arrival, not about legibility: anything we
        // saw here and did not turn into a half means we cannot call its
        // sender absent.
        unreadable.add(event.senderId);
        continue;
      }

      final content = CallTranscriptContent.fromJson(event.content);
      if (content == null) {
        unreadable.add(event.senderId);
        continue;
      }

      // A half whose content names a different call is not this call's, even
      // though the server returned it under this anchor. Not placed -- and
      // not forgotten either. The rule above is about ARRIVAL, and carving
      // this one case out of it is how the same mistake survived a round: a
      // legible event that says it belongs elsewhere still tells us nothing
      // about whether its sender wrote a half HERE, so calling them silent
      // remains a claim we cannot support. It is also self-declared, and the
      // server's anchor says otherwise.
      if (content.callKey != callKey) {
        unreadable.add(event.senderId);
        continue;
      }

      candidates.add(
        TranscriptCandidate(
          senderId: event.senderId,
          originServerTs: event.originServerTs.millisecondsSinceEpoch,
          segments: content.segments,
          accounting: content.accounting,
          // Carried, not derived here. `originServerTs` beside it is the
          // SERVER's receive time and is deliberately never used to correct a
          // clock -- a slow send would read as skew, and under federation the
          // two halves' timestamps come from two homeservers. The anchor is
          // the writing device's own measurement against the SFU.
          clockAnchor: content.clockAnchor,
          positionsMarked: content.positionsMarked,
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

  final transcript = assembleTranscript(
    candidates: candidates,
    expectedSenders: expectedSenders,
    participantsKnown: participantsKnown,
    // An encrypted room is never an exhausted read, whatever the server said
    // about paging: we reached the end of a list we could not read.
    exhausted: exhausted && !encrypted,
    unreadableSenders: unreadable,
  );

  // Recorded for every half that is not clean, by default and at read time.
  //
  // The four states tell the learner what to say; they do not say what went
  // wrong, and several different failures reach the same state. Without this,
  // "it said I said nothing" is unanswerable after the fact -- the raw event
  // is the only evidence and nobody has it. One line per unclean half, naming
  // the cause and the counts behind it, is what makes such a report
  // diagnosable instead of a guess.
  for (final half in transcript.halves) {
    final issue = half.issue;
    if (issue == HalfIssue.none) continue;
    // A ROLE, not a user id. Every other log in this feature keeps
    // participant identity out, and this one paired a durable,
    // cross-call-correlatable Matrix id with a capture failure. The call key
    // already distinguishes the halves of one call, which is all the
    // diagnosis needs.
    final role = half.senderId == selfId ? 'self' : 'peer';
    Logs().i(
      'Call transcript half not clean: ${issue.name} '
      'for $role on $callKey '
      '(state ${half.state.name}, '
      'captured ${half.accounting.chunksCaptured}, '
      'transcribed ${half.accounting.chunksTranscribed}, '
      'lost ${half.accounting.chunksLost}, '
      'micRefused ${half.accounting.captureRefused}, '
      'drained ${half.accounting.drainComplete}, '
      'declared ${half.accounting.declared}, '
      'omitted ${half.accounting.segmentsOmitted}, '
      // Both, unconditionally, because `issue` reports only ONE cause and
      // these two sit last in its order -- so any other problem hides them.
      // A report about turns in the wrong order is exactly the report that
      // needs to know how many of them were only bounded to a chunk, and
      // whether the writer said which were not.
      'positionsMarked ${half.positionsMarked}, '
      'approximate ${half.approximatePositions})',
    );
  }

  return transcript;
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
