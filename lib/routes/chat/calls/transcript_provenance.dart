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

  const FetchedAudioEvent({
    required this.senderId,
    this.redacted = false,
    this.content,
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
      );
    };

/// What one direct fetch of a source audio event came to, before it is checked
/// against a particular claim.
enum _AudioResolutionKind {
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
class _AudioResolution {
  final _AudioResolutionKind kind;

  /// Who uploaded the audio, when [kind] is [_AudioResolutionKind.resolved].
  final String? senderId;

  /// The parsed content, when [kind] is [_AudioResolutionKind.resolved].
  final CallAudioContent? content;

  const _AudioResolution._(this.kind, {this.senderId, this.content});

  const _AudioResolution.pending() : this._(_AudioResolutionKind.pending);
  const _AudioResolution.gone() : this._(_AudioResolutionKind.gone);
  const _AudioResolution.notCallAudio()
    : this._(_AudioResolutionKind.notCallAudio);
  _AudioResolution.resolved(String senderId, CallAudioContent content)
    : this._(
        _AudioResolutionKind.resolved,
        senderId: senderId,
        content: content,
      );

  /// Whether this resolution is a real per-device recording by a participant
  /// for this call — the unit a manifest's VALIDATED coverage is counted in.
  ///
  /// A source id that resolves to a stranger's event, a foreign call, or a
  /// recording that names no device is not a validated unit: it cannot anchor a
  /// `(call, speaker, device)` half, so it must not lend a manifest coverage it
  /// then cannot back.
  bool isValidatedUnitFor(Set<String> participants, String callKey) =>
      kind == _AudioResolutionKind.resolved &&
      participants.contains(senderId) &&
      content!.callKey == callKey &&
      content!.deviceId != null;
}

Future<_AudioResolution> _resolveOnce(
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
    if (event == null || event.redacted) return const _AudioResolution.gone();
    final content = event.content;
    if (content == null) return const _AudioResolution.notCallAudio();
    return _AudioResolution.resolved(event.senderId, content);
  } catch (_) {
    // The fetch itself failed. TRANSIENT: held pending, resolves on a later
    // rebuild, and -- the point of catching rather than rethrowing -- never
    // conflated with "the audio is gone".
    return const _AudioResolution.pending();
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
/// A manifest that validates NOTHING is not selected: its coverage says nothing
/// at all, and treating it as "the manifest" would turn every real peer half
/// into a not-in-manifest reject (attributed to its writer) on the strength of a
/// flood. With no genuine manifest, peer claims stay pending until one arrives.
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

  // One fetch per source id, reused across manifest validation and per-claim
  // resolution. This is what bounds fetches by manifest size rather than by the
  // number of claims: the second reference to an id is a cache hit.
  final cache = <String, Future<_AudioResolution>>{};
  Future<_AudioResolution> resolve(String id) =>
      cache.putIfAbsent(id, () => _resolveOnce(fetch, roomId, id));

  // Participant-authored merges of THIS call. `fetchCallAudioMerged` already
  // refuses a foreign call key; the checks here are cheap and defensive.
  final manifests = [
    for (final merged in mergedRecordings)
      if (participants.contains(merged.senderId) &&
          merged.content.callKey == callKey)
        merged,
  ];

  // Validated coverage per manifest, counted over its own source ids
  // (de-duplicated defensively -- `fromJson` already canonicalises, but the
  // count must not depend on that continuing to hold).
  //
  // A TRANSIENT fetch during validation makes the SELECTION uncertain: a source
  // that would have validated the true manifest resolves pending, so that
  // manifest is undercounted and a different one may be selected. That must not
  // TERMINALLY reject a real peer half whose source is only in the true
  // manifest -- the miss was transient, and a rebuild re-fetches. So it is
  // tracked and threaded into per-claim resolution below.
  final validatedCounts = <String, int>{};
  var selectionUncertain = false;
  for (final manifest in manifests) {
    var validated = 0;
    for (final id in manifest.content.sourceEventIds.toSet()) {
      final resolution = await resolve(id);
      if (resolution.kind == _AudioResolutionKind.pending) {
        selectionUncertain = true;
      }
      if (resolution.isValidatedUnitFor(participants, callKey)) validated++;
    }
    validatedCounts[manifest.eventId] = validated;
  }

  final selected = _selectManifest(manifests, validatedCounts);
  // The membership set is the SELECTED manifest's own source ids -- the FULL
  // set, not the validated subset. A source that is listed but has since been
  // redacted must resolve to "audio unavailable" (it IS in the manifest), not
  // to "not in the manifest".
  final manifestIds = selected?.content.sourceEventIds.toSet();

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

Future<ProvenanceState> _resolvePeerClaim({
  required TranscriptCandidate candidate,
  required Set<String> participants,
  required String callKey,
  required Set<String>? manifestIds,
  required bool selectionUncertain,
  required Future<_AudioResolution> Function(String id) resolve,
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
    case _AudioResolutionKind.pending:
      return ProvenanceState.pendingTransient;
    case _AudioResolutionKind.gone:
      // In the manifest but its media is gone: "audio unavailable", not words,
      // and not a fallback to the writer.
      return ProvenanceState.unavailableTerminal;
    case _AudioResolutionKind.notCallAudio:
      return ProvenanceState.invalidTerminal;
    case _AudioResolutionKind.resolved:
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
