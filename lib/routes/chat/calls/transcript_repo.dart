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

  /// Resolves the provenance of the PEER-PRODUCED halves among [candidates],
  /// returning a [ProvenanceState] per candidate event id for
  /// [assembleTranscript] to consume.
  ///
  /// Injected rather than reached for, exactly as [fetch] is, and for the same
  /// reason: the verdict needs the call's audio manifest and a per-event fetch,
  /// which a test must be able to stand in for. It is handed the parsed
  /// candidates because only this function has read them off the wire.
  ///
  /// ABSENT is the legacy path. With no resolver, no `spokenBy` claim can be
  /// honoured, so every candidate that carries one is left in
  /// [ProvenanceState.pendingTransient] by assembly's own default — held out of
  /// the words, never collapsed to its writer. A read with no peer halves at all
  /// (every candidate authentic) is wholly unaffected whether this is set or
  /// not, which is what keeps the flag-off client's behaviour identical.
  Future<Map<String, ProvenanceState>> Function(
    List<TranscriptCandidate> candidates,
  )?
  resolveProvenance,
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
          // The transcript event's own id: the deterministic final tie-break in
          // the cross-writer dedup order, and the key a provenance verdict is
          // computed against.
          eventId: event.eventId,
          // The event's SENDER is the account and the content's device id is
          // the recorder, and assembly needs both: two of one learner's devices
          // in one call send two events with the same sender.
          deviceId: content.deviceId,
          // Whose speech this half claims to be, and the audio it was
          // transcribed from, when the writer is not the speaker. Carried
          // untouched for the provenance resolver to rule on; absent on an
          // authentic half, which assembly treats as the sender's own.
          spokenBy: content.spokenBy,
          sourceAudioEventId: content.sourceAudioEventId,
          originServerTs: event.originServerTs.millisecondsSinceEpoch,
          segments: content.segments,
          accounting: content.accounting,
          // Carried, not derived here. `originServerTs` beside it is the
          // SERVER's receive time and is deliberately never used to correct a
          // clock -- a slow send would read as skew, and under federation the
          // two halves' timestamps come from two homeservers. The anchor is
          // the writing device's own measurement against the SFU.
          clockAnchor: content.clockAnchor,
          // Carried like the anchor above, so the view can tokenize the words
          // in the language this half was transcribed in.
          langCode: content.langCode,
          positionsMarked: content.positionsMarked,
          // What this device says it holds, and what it says it handed over.
          // Carried through untouched, like the anchor above: assembly is the
          // only place that can compare one device's statement with another's.
          keptSpans: content.keptSpans,
          discardedSpans: content.discardedSpans,
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

  // Peer-produced halves -- those naming a speaker other than their writer --
  // need their provenance resolved against the call's audio manifest before
  // assembly can attribute them. Authentic halves need none, so the resolver is
  // invoked ONLY when a peer claim is actually present: a call with no peer
  // halves costs no manifest read whether or not a resolver was supplied, which
  // is every legacy and flag-off read. With no resolver but a peer claim
  // present, the map is empty and assembly holds that claim out as pending --
  // never its writer's -- which is the safe direction.
  //
  // A THROW falls back to that same safe direction. The production resolver
  // reaches the network (the audio manifest fetch and a per-event fetch), and
  // only its per-event fetches catch their own failure -- the manifest relations
  // fetch can still throw. Letting that propagate would fail the WHOLE read and
  // hide the AUTHENTIC halves too, telling both speakers the other said nothing
  // off a read that merely could not check provenance. So it is caught here and
  // treated as no verdict: every peer claim held pending, every authentic half
  // rendered.
  var provenance = const <String, ProvenanceState>{};
  if (resolveProvenance != null && candidates.any((c) => c.spokenBy != null)) {
    try {
      provenance = await resolveProvenance(candidates);
    } catch (e, s) {
      Logs().w(
        'Call transcript provenance could not be resolved on $callKey; '
        'holding every peer claim pending and rendering the authentic halves',
        e,
        s,
      );
    }
  }

  final transcript = assembleTranscript(
    candidates: candidates,
    expectedSenders: expectedSenders,
    participantsKnown: participantsKnown,
    provenance: provenance,
    // An encrypted room is never a read this reader may conclude from,
    // whatever the server said about paging: we reached the end of a list we
    // could not read. It travels as ITSELF and is no longer folded into
    // `exhausted`, which is what made it indistinguishable downstream from our
    // own page ceiling -- so the screen offered "too much to read in one go"
    // for a room it simply could not decrypt.
    exhausted: exhausted,
    encrypted: encrypted,
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
      // Printed even though it is not a gap on its own. It is the ONE count
      // that can explain an empty half nobody else can account for, and a
      // report of "it said I said nothing" is exactly the report that needs
      // to see it.
      'suppressed ${half.accounting.chunksSuppressed}, '
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
      'approximate ${half.approximatePositions}, '
      // Unconditional, for the same reason as the two above and one more
      // besides. `issue` reports ONE cause and this one deliberately sits below
      // every writer failure, so any of those would hide it -- and this is the
      // count that makes duplicate credit countable at all. Two devices that
      // both recorded and both wrote are two devices that both claimed the same
      // speech; nothing in the client stops that being credited twice, and a
      // number here is what turns "it might be happening" into a figure.
      //
      // A COUNT and never the device ids. Every log in this feature keeps
      // participant identity out, and the call key already distinguishes the
      // halves of one call, which is all the diagnosis needs.
      'devices ${half.deviceCount})',
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
