/// The anti-forgery core of the whole-call transcript (#8792): turning each
/// peer-produced half's `spokenBy` CLAIM into a resolved [ProvenanceState].
///
/// A 1:1 DM has exactly two members, so every event is one participant's, and a
/// half can only be forged onto a name that IS on the call. A subscriber may
/// transcribe the OTHER participant's saved audio and post it (`spokenBy` names
/// the peer, `sourceAudioEventId` points at the peer's own recording); trust
/// reduces to "this participant's device uploaded this audio for this call".
/// Everything here exists to check exactly that, against the call's merged-event
/// audio MANIFEST, and to hand [assembleTranscript] a STATE it consumes — never
/// a name it collapses to the sender.
///
/// The read path is: [resolveTranscriptProvenance] selects one manifest,
/// resolves each peer claim against it, and returns a state per transcript event
/// id; `assembleTranscript` reads those states. Both halves are separately
/// testable — the selection and the state machine here with a fake
/// [AudioEventFetcher], the attribution there with a fixed state map.
library;

import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_closure.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

/// One `pangea.call_audio` event fetched by id, normalized to what provenance
/// needs to rule on it.
///
/// The reader never plays audio here; it only checks who uploaded what. So this
/// carries the sender, whether the event's content is gone (redacted), and the
/// parsed [CallAudioContent] when there is one — nothing more.
class FetchedAudioEvent {
  /// Who posted the audio event — the claimed speaker, if the claim is true.
  final String senderId;

  /// The event exists but its content has been stripped (redacted). Its audio
  /// can no longer be played, which is a DIFFERENT fact from the event never
  /// existing: it resolves to [ProvenanceState.unavailableTerminal], not to a
  /// retry and not to the writer's own words.
  final bool redacted;

  /// The parsed `pangea.call_audio` content, or null when the event is not one
  /// (a different type, or redacted so its content is gone).
  final CallAudioContent? content;

  /// When the event landed on the server. The reader does not use it (it only
  /// checks who uploaded what); it is here so the whole-call transcriber's
  /// discovery can build a [CallAudioRecording] from the SAME resolution it
  /// validated a source with, rather than fetching the event a second time.
  /// Optional and null when a caller did not supply it — a real fetch always
  /// does (see [audioEventFetcherFor]).
  final DateTime? originServerTs;

  const FetchedAudioEvent({
    required this.senderId,
    this.redacted = false,
    this.content,
    this.originServerTs,
  });
}

/// Fetches one event by id for provenance resolution.
///
/// Injected exactly as `RelationsFetcher` is, and for the same reason: the
/// resolution rules are the part most likely to be wrong and the hardest to
/// provoke against a real server, so they must be testable without one.
///
/// The three outcomes are three DIFFERENT answers and must stay distinct:
/// * a [FetchedAudioEvent] — the event was found (see its own fields for what
///   was found);
/// * `null` — the server does not have it (redacted-and-purged, or an id that
///   never existed). TERMINAL: no retry produces it;
/// * a THROW — the fetch itself failed and may yet succeed. TRANSIENT.
///
/// Conflating the last two is the mistake this seam is shaped to prevent: a
/// network blip is not "the audio is gone", and "gone" is not "try again
/// forever".
typedef AudioEventFetcher =
    Future<FetchedAudioEvent?> Function({
      required String roomId,
      required String eventId,
    });

/// The [AudioEventFetcher] that talks to a real homeserver.
///
/// [Room.getEventById] searches the local cache then the server, returns null
/// on `M_NOT_FOUND`, and throws on anything else — which is exactly the seam's
/// contract, so nothing is caught here. A redacted event still resolves, with
/// its content stripped; the flag is read straight off it. The type gate is the
/// same one every other call-event reader applies: a relation-less fetch by id
/// can return anything, and only an exact `pangea.call_audio` is one.
AudioEventFetcher audioEventFetcherFor(Room room) =>
    ({required String roomId, required String eventId}) async {
      final event = await room.getEventById(eventId);
      if (event == null) return null;
      final redacted = event.redacted;
      // Parsed only from a live event of the exact type. A redacted event's
      // content is gone, and a fetch by id (unlike a relations query) is not
      // even scoped to a type, so both must be excluded before parsing or the
      // resolver would read invented content off the wrong event.
      final content = !redacted && event.type == CallAudioContent.relType
          ? CallAudioContent.fromJson(event.content)
          : null;
      return FetchedAudioEvent(
        senderId: event.senderId,
        redacted: redacted,
        content: content,
        originServerTs: event.originServerTs,
      );
    };

/// What one direct fetch of a source audio event came to, before it is checked
/// against a particular claim.
enum AudioResolutionKind {
  /// The fetch failed transiently and may yet succeed.
  pending,

  /// The event is not on the server, or is redacted: its audio is gone.
  gone,

  /// The event resolved but is not a `pangea.call_audio` at all.
  notCallAudio,

  /// The event resolved to a parseable `pangea.call_audio`.
  resolved,
}

/// One fetch's outcome, memoized so a source id is fetched at most once whether
/// it is reached through manifest validation or through a peer claim.
///
/// Public so the whole-call transcriber's discovery can validate a manifest's
/// sources by the SAME rule the reader's provenance does (via
/// [selectCallAudioManifest]) rather than a divergent copy.
class AudioResolution {
  final AudioResolutionKind kind;

  /// Who uploaded the audio, when [kind] is [AudioResolutionKind.resolved].
  final String? senderId;

  /// The parsed content, when [kind] is [AudioResolutionKind.resolved].
  final CallAudioContent? content;

  /// When the resolved source event landed, when [kind] is
  /// [AudioResolutionKind.resolved] and the fetch supplied it. Carried so the
  /// producer's discovery can build a [CallAudioRecording] from THIS resolution
  /// rather than a second fetch; the reader ignores it.
  final DateTime? originServerTs;

  const AudioResolution._(
    this.kind, {
    this.senderId,
    this.content,
    this.originServerTs,
  });

  const AudioResolution.pending() : this._(AudioResolutionKind.pending);
  const AudioResolution.gone() : this._(AudioResolutionKind.gone);
  const AudioResolution.notCallAudio()
    : this._(AudioResolutionKind.notCallAudio);
  AudioResolution.resolved(
    String senderId,
    CallAudioContent content, [
    DateTime? originServerTs,
  ]) : this._(
         AudioResolutionKind.resolved,
         senderId: senderId,
         content: content,
         originServerTs: originServerTs,
       );

  /// Whether this resolution is a real per-device recording by a participant
  /// for this call — the unit a manifest's VALIDATED coverage is counted in.
  ///
  /// A source id that resolves to a stranger's event, a foreign call, or a
  /// recording that names no device is not a validated unit: it cannot anchor a
  /// `(call, speaker, device)` half, so it must not lend a manifest coverage it
  /// then cannot back.
  bool isValidatedUnitFor(Set<String> participants, String callKey) =>
      kind == AudioResolutionKind.resolved &&
      participants.contains(senderId) &&
      content!.callKey == callKey &&
      content!.deviceId != null;
}

/// Resolves one source audio event by id to an [AudioResolution]. A memoized
/// instance is what bounds fetches by manifest size rather than by claim count.
typedef AudioResolver = Future<AudioResolution> Function(String eventId);

/// A memoized [AudioResolver] over [fetch] for [roomId]: each source id is
/// fetched at most once, whether it is reached through manifest validation, a
/// peer claim, or the whole-call transcriber's discovery. Both the reader
/// ([resolveTranscriptProvenance]) and the producer share ONE of these per
/// invocation so their manifest selection cannot diverge and their fetches stay
/// bounded by the number of distinct source ids.
AudioResolver audioResolverFor(AudioEventFetcher fetch, String roomId) {
  final cache = <String, Future<AudioResolution>>{};
  return (eventId) =>
      cache.putIfAbsent(eventId, () => _resolveOnce(fetch, roomId, eventId));
}

Future<AudioResolution> _resolveOnce(
  AudioEventFetcher fetch,
  String roomId,
  String eventId,
) async {
  try {
    final event = await fetch(roomId: roomId, eventId: eventId);
    // Not on the server, or found-but-redacted: the audio is gone either way.
    // Terminal, and distinct from a transient failure below -- a redaction is
    // not a network blip, and reporting it as retryable would leave the half
    // pending forever.
    if (event == null || event.redacted) return const AudioResolution.gone();
    final content = event.content;
    if (content == null) return const AudioResolution.notCallAudio();
    return AudioResolution.resolved(
      event.senderId,
      content,
      event.originServerTs,
    );
  } catch (_) {
    // The fetch itself failed. TRANSIENT: held pending, resolves on a later
    // rebuild, and -- the point of catching rather than rethrowing -- never
    // conflated with "the audio is gone".
    return const AudioResolution.pending();
  }
}

/// A total order over candidate manifests: greatest VALIDATED coverage first,
/// then the manifest-specific tie-break.
///
/// Whether [manifest] (with [count] validated units) ranks strictly above
/// [best] (with [bestCount]). Coverage is the VALIDATED count, never the raw
/// [CallAudioMergedContent.coverageCardinality] -- a flood of 64 bogus source
/// ids has cardinality 64 and validated coverage 0, and must not outrank a real
/// two-source merge. Ties break by earliest `originServerTs`, then lower sender
/// id, then lower merged event id: the merged event carries no sender DEVICE id
/// to order by (unlike a transcript half), and its globally-unique event id
/// makes the order total on its own.
bool _manifestOutranks(
  CallAudioMergedRecording manifest,
  int count,
  CallAudioMergedRecording best,
  int bestCount,
) {
  if (count != bestCount) return count > bestCount;
  final byTs = manifest.originServerTs.compareTo(best.originServerTs);
  if (byTs != 0) return byTs < 0;
  final bySender = manifest.senderId.compareTo(best.senderId);
  if (bySender != 0) return bySender < 0;
  return manifest.eventId.compareTo(best.eventId) < 0;
}

/// The one manifest to resolve peer claims against, or null when none is
/// genuine yet.
///
/// Only a trusted manifest has a count at all: a flood, a partial merge or one
/// listing anything that is not a participant's recording of this call is never
/// "the manifest", so it cannot turn real peer halves into not-in-manifest
/// rejects. With no trusted manifest, peer claims stay pending until one
/// arrives.
CallAudioMergedRecording? _selectManifest(
  List<CallAudioMergedRecording> manifests,
  Map<String, int> validatedCounts,
) {
  CallAudioMergedRecording? best;
  var bestCount = 0;
  for (final manifest in manifests) {
    final count = validatedCounts[manifest.eventId] ?? 0;
    if (count == 0) continue;
    if (best == null || _manifestOutranks(manifest, count, best, bestCount)) {
      best = manifest;
      bestCount = count;
    }
  }
  return best;
}

/// Selects the ONE manifest to trust for a call, and reports whether that
/// selection was made under uncertainty.
///
/// This is the single manifest-selection the reader and the whole-call
/// transcriber's discovery BOTH call, so a produced peer half's
/// `sourceAudioEventId` is in the manifest the reader will select — never an
/// alternate the producer chose by list order or on a transient miss.
///
/// The rule: among the participant-authored merges of THIS call, only a
/// TRUSTED merge of the whole call it covers counts (`isTrustedWholeMerge`,
/// client#9173) -- every listed source resolves through [resolve] to a
/// validated unit and those units close into the whole call -- and the greatest
/// is picked by [_selectManifest]'s total order (coverage, then earliest ts,
/// then sender id, then merged event id). [uncertain] is true when any
/// validation fetch came back
/// [AudioResolutionKind.pending]: the true manifest may have been undercounted,
/// so a caller must NOT commit to the selection — the reader holds affected
/// claims pending, and the producer treats it as "no manifest yet" and retries.
///
/// FETCHES ARE BOUNDED BY THE NUMBER OF DISTINCT SOURCE IDS, never by claim
/// count, because [resolve] is memoized: a source referenced by many claims, or
/// by both validation and a claim, costs one fetch.
Future<({CallAudioMergedRecording? manifest, bool uncertain})>
selectCallAudioManifest({
  required List<CallAudioMergedRecording> mergedRecordings,
  required Set<String> participants,
  required String callKey,
  required AudioResolver resolve,
}) async {
  // Participant-authored merges of THIS call. `fetchCallAudioMerged` already
  // refuses a foreign call key; the checks here are cheap and defensive.
  final manifests = [
    for (final merged in mergedRecordings)
      if (participants.contains(merged.senderId) &&
          merged.content.callKey == callKey)
        merged,
  ];

  // Only a TRUSTED merge of the whole call it covers is a manifest
  // (client#9173): every listed source must resolve to a participant's own
  // recording of this call, those recordings must close into the whole call
  // (`closeCall`), and the merge must cover exactly them -- the same test the
  // merge coordinator retires a call on and the view shows a merge on. One
  // source that is not a validated unit disqualifies the merge; one that could
  // not be looked up makes the selection uncertain rather than deciding.
  final trustedCounts = <String, int>{};
  var uncertain = false;
  for (final manifest in manifests) {
    final halves = <CallAudioRecording>[];
    var usable = true;
    for (final id in manifest.content.sourceEventIds.toSet()) {
      final resolution = await resolve(id);
      if (resolution.kind == AudioResolutionKind.pending) {
        uncertain = true;
        usable = false;
        continue;
      }
      if (!resolution.isValidatedUnitFor(participants, callKey)) {
        usable = false;
        continue;
      }
      halves.add(
        CallAudioRecording(
          eventId: id,
          senderId: resolution.senderId!,
          originServerTs: resolution.originServerTs ?? manifest.originServerTs,
          content: resolution.content!,
        ),
      );
    }
    if (!usable) continue;
    final closure = closeCall(halves, participants);
    if (closure is! ClosedCall) continue;
    if (!isTrustedWholeMerge(
      merged: manifest,
      closed: closure,
      participants: participants,
      callKey: callKey,
    )) {
      continue;
    }
    trustedCounts[manifest.eventId] = halves.length;
  }

  return (
    manifest: _selectManifest(manifests, trustedCounts),
    uncertain: uncertain,
  );
}

/// Resolves the provenance of every peer-produced half among [candidates].
///
/// Returns a [ProvenanceState] per PEER candidate, keyed by its transcript event
/// id, for [assembleTranscript] to consume. Authentic halves (no `spokenBy`) are
/// absent from the result and need no resolution — they are their own sender's.
///
/// The steps, in order, are the anti-forgery argument:
/// 1. select ONE manifest — participant-authored, this call's, greatest
///    VALIDATED coverage (see [_selectManifest]);
/// 2. for each peer claim, reject the cheap terminal cases before any fetch (no
///    source id, or a `spokenBy` that is not a participant -> INVALID), hold out
///    when there is no manifest yet (-> PENDING), reject a source id that is not
///    in the selected manifest (-> INVALID, by set membership, no fetch), and
///    otherwise resolve the in-manifest source and check it names [spokenBy] for
///    this call and device.
///
/// FETCHES ARE BOUND BY MANIFEST SIZE, NEVER BY CLAIM COUNT. Every source fetch
/// is memoized, so ten thousand peer claims that reference the same audio cost
/// one fetch, and a claim whose source is not in the manifest costs none. A
/// flood of bogus manifests or halves can neither outrank the real manifest nor
/// exhaust the resolver.
Future<Map<String, ProvenanceState>> resolveTranscriptProvenance({
  required List<TranscriptCandidate> candidates,
  required List<CallAudioMergedRecording> mergedRecordings,
  required Set<String> participants,
  required String callKey,
  required String roomId,
  required AudioEventFetcher fetch,
}) async {
  final peers = [
    for (final candidate in candidates)
      if (candidate.spokenBy != null) candidate,
  ];
  if (peers.isEmpty) return const {};

  // One memoized resolver, shared with the manifest selection below AND reused
  // for per-claim resolution -- this is what bounds fetches by the number of
  // distinct source ids rather than by claim count: the second reference to an
  // id is a cache hit.
  final resolve = audioResolverFor(fetch, roomId);

  // The one manifest to trust, selected the SAME way the whole-call
  // transcriber's discovery selects it (both call [selectCallAudioManifest]), so
  // a produced peer half's source is in the manifest this reader will select.
  //
  // A TRANSIENT fetch during validation makes the selection UNCERTAIN: a source
  // that would have validated the true manifest resolves pending, so that
  // manifest is undercounted and a different one may be selected. That must not
  // TERMINALLY reject a real peer half whose source is only in the true
  // manifest -- the miss was transient, and a rebuild re-fetches. So it is
  // threaded into per-claim resolution below.
  final selection = await selectCallAudioManifest(
    mergedRecordings: mergedRecordings,
    participants: participants,
    callKey: callKey,
    resolve: resolve,
  );
  final selectionUncertain = selection.uncertain;
  // The membership set is the SELECTED manifest's own source ids -- the FULL
  // set, not the validated subset. A source that is listed but has since been
  // redacted must resolve to "audio unavailable" (it IS in the manifest), not
  // to "not in the manifest".
  //
  // With no trusted manifest, a participant's merge whose every listed source
  // is either a validated recording or GONE (redacted, not found) still
  // answers claims: it is untrusted only because audio was removed, so a claim
  // naming the removed audio is "audio unavailable" -- terminal, as before
  // client#9173 -- rather than waiting forever. It is never shown or used to
  // retire the call.
  final manifestIds =
      (selection.manifest ??
              await _manifestMissingOnlyGoneAudio(
                mergedRecordings: mergedRecordings,
                participants: participants,
                callKey: callKey,
                resolve: resolve,
              ))
          ?.content
          .sourceEventIds
          .toSet();

  final result = <String, ProvenanceState>{};
  for (final candidate in peers) {
    result[candidate.eventId] = await _resolvePeerClaim(
      candidate: candidate,
      participants: participants,
      callKey: callKey,
      manifestIds: manifestIds,
      selectionUncertain: selectionUncertain,
      resolve: resolve,
    );
  }
  return result;
}

/// The first participant's merge of this call whose listed sources are all
/// validated recordings or gone, with at least one of each; null when none
/// is.
/// Pending sources disqualify (the caller is already uncertain), as does any
/// source that resolved to something that is not this call's recording.
Future<CallAudioMergedRecording?> _manifestMissingOnlyGoneAudio({
  required List<CallAudioMergedRecording> mergedRecordings,
  required Set<String> participants,
  required String callKey,
  required AudioResolver resolve,
}) async {
  for (final merged in mergedRecordings) {
    if (!participants.contains(merged.senderId) ||
        merged.content.callKey != callKey) {
      continue;
    }
    var gone = 0;
    var validated = 0;
    var usable = true;
    for (final id in merged.content.sourceEventIds.toSet()) {
      final resolution = await resolve(id);
      if (resolution.kind == AudioResolutionKind.gone) {
        gone++;
      } else if (resolution.isValidatedUnitFor(participants, callKey)) {
        validated++;
      } else {
        usable = false;
        break;
      }
    }
    // At least one real recording: a flood of ids that resolve to nothing is
    // not a merge whose audio was removed.
    if (usable && gone > 0 && validated > 0) return merged;
  }
  return null;
}

Future<ProvenanceState> _resolvePeerClaim({
  required TranscriptCandidate candidate,
  required Set<String> participants,
  required String callKey,
  required Set<String>? manifestIds,
  required bool selectionUncertain,
  required AudioResolver resolve,
}) async {
  final spokenBy = candidate.spokenBy!;
  final sourceId = candidate.sourceAudioEventId;

  // Terminal cheap rejects, before any manifest or fetch. A peer half with no
  // source to anchor it, or naming a speaker who is not one of the two people
  // on the call, can NEVER become valid -- so it falls to its writer (the
  // legacy shape) now rather than waiting on a manifest that cannot rescue it.
  // These stay terminal even when selection is uncertain: no manifest, present
  // or future, makes a device-less anchor or a stranger's name valid.
  if (sourceId == null) return ProvenanceState.invalidTerminal;
  if (!participants.contains(spokenBy)) return ProvenanceState.invalidTerminal;

  // No genuine manifest yet -- the merge may still arrive. Held pending, never
  // attributed: "we cannot check this yet" is not "the writer said it".
  if (manifestIds == null) return ProvenanceState.pendingTransient;

  // Not in the SELECTED manifest. Ordinarily a terminal reject by cheap set
  // membership, before any fetch -- which is what a flood of transcript halves
  // referencing bogus audio ids costs: nothing, and no forged attribution.
  //
  // BUT when selection was uncertain (a validation fetch was transient), the
  // wrong manifest may have been selected and THIS source may belong to the
  // true one. Rejecting it terminally would bury a real half on a transient
  // miss, so it is held PENDING -- a rebuild re-fetches, the true manifest is
  // selected, and it resolves correctly. A genuinely bogus id stays out either
  // way; the cost is only that it is retried rather than rejected at once.
  if (!manifestIds.contains(sourceId)) {
    return selectionUncertain
        ? ProvenanceState.pendingTransient
        : ProvenanceState.invalidTerminal;
  }

  final resolution = await resolve(sourceId);
  switch (resolution.kind) {
    case AudioResolutionKind.pending:
      return ProvenanceState.pendingTransient;
    case AudioResolutionKind.gone:
      // In the manifest but its media is gone: "audio unavailable", not words,
      // and not a fallback to the writer.
      return ProvenanceState.unavailableTerminal;
    case AudioResolutionKind.notCallAudio:
      return ProvenanceState.invalidTerminal;
    case AudioResolutionKind.resolved:
      // The whole of the honoured claim: the source is the NAMED speaker's own
      // recording, for THIS call, from the SAME device the half is keyed by. A
      // failure of any one of these is the writer's own (legacy) half, never the
      // speaker's -- so a name is bound to audio it cannot forge.
      //
      // BOTH device ids must be present, not merely equal. Two absent device
      // ids are `null == null` -- true -- which would bind a device-less half to
      // a device-less recording on no shared identity at all. A unit is
      // (call, speaker, device), and there is no unit without a device, so a
      // device-less half is never VALID however the audio resolves.
      final valid =
          resolution.senderId == spokenBy &&
          resolution.content!.callKey == callKey &&
          candidate.deviceId != null &&
          resolution.content!.deviceId != null &&
          resolution.content!.deviceId == candidate.deviceId;
      return valid ? ProvenanceState.valid : ProvenanceState.invalidTerminal;
  }
}
