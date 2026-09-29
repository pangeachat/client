import 'dart:math';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_download.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/recording_transcription.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_provenance.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/calls/transcript_writer.dart';

import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart'
    show ChunkTranscriber;

/// The set of recordings a call's audio manifest names, and whether a genuine
/// manifest was found at all.
///
/// [resolved] is the merge-arrival signal: false means no `pangea.call_audio_merged`
/// manifest with any validated source is visible yet (the merge may still be in
/// flight), which is what the call-end path retries on. When it is true,
/// [recordings] is the complete set of the call's per-device recordings the
/// selected manifest names -- complete because it comes from the manifest's own
/// `sourceEventIds`, not the relations page the recording events happen to sit
/// on, so a deep-paged recording is still listed.
class WholeCallManifest {
  final bool resolved;
  final List<CallAudioRecording> recordings;

  const WholeCallManifest({required this.resolved, this.recordings = const []});

  static const absent = WholeCallManifest(resolved: false);
}

/// Discovers a call's recordings from its audio manifest, selecting the manifest
/// the SAME way the reader's provenance does — via [selectCallAudioManifest], so
/// a produced peer half's `sourceAudioEventId` is in the manifest the reader
/// will select, never an alternate chosen by list order or on a transient miss.
///
/// Returns [WholeCallManifest.absent] (NOT resolved) when no participant manifest
/// validates anything yet OR when the selection was UNCERTAIN (a validation fetch
/// came back transient): committing to an alternate on a transient is exactly the
/// divergence that would make the reader mark the produced half invalid, so the
/// merge-arrival retry handles it instead. When a manifest is chosen, each of its
/// source ids is turned into a [CallAudioRecording] by [recordingFor] and kept
/// only when it is a validated unit — a participant's own recording for this call
/// with a device.
///
/// The recordings are built from the SAME memoized [resolve] result the
/// selection validated each source with — ONE fetch per source, and no second,
/// separately-failing fetch that could return null for a source that already
/// validated and thereby drop a real half while `resolved` stayed true. Because
/// selection reports `uncertain` on ANY transient during validation (returning
/// absent here, so the retry re-runs), there is no post-selection fetch left
/// that can transiently drop a validated source. [resolve] is injected, so this
/// is unit-tested with a fake and no homeserver.
Future<WholeCallManifest> discoverWholeCallManifest({
  required List<CallAudioMergedRecording> mergedRecordings,
  required Set<String> participants,
  required String callKey,
  required AudioResolver resolve,
}) async {
  final selection = await selectCallAudioManifest(
    mergedRecordings: mergedRecordings,
    participants: participants,
    callKey: callKey,
    resolve: resolve,
  );
  final manifest = selection.manifest;
  if (manifest == null || selection.uncertain) return WholeCallManifest.absent;

  final recordings = <CallAudioRecording>[];
  for (final id in manifest.content.sourceEventIds.toSet()) {
    final resolution = await resolve(
      id,
    ); // memoized: a cache hit after selection
    // Only a validated unit becomes a backfill target -- a participant's own
    // recording for this call with a device -- the same rule the selection
    // counted coverage by. `isValidatedUnitFor` guarantees kind == resolved, so
    // senderId/content are present; a resolution from the real fetcher (or the
    // test fake) always carries originServerTs.
    if (resolution.isValidatedUnitFor(participants, callKey)) {
      recordings.add(
        CallAudioRecording(
          eventId: id,
          senderId: resolution.senderId!,
          originServerTs: resolution.originServerTs!,
          content: resolution.content!,
        ),
      );
    }
  }
  return WholeCallManifest(resolved: true, recordings: recordings);
}

/// Discovers the call's recordings from its audio manifest. See
/// [WholeCallManifest]. Injected so discovery -- manifest selection and the
/// per-source fetches behind it -- is exercised in the coordinator's tests with
/// a plain list rather than a homeserver.
typedef ManifestDiscoverer = Future<WholeCallManifest> Function(String callKey);

/// Reads the call's ASSEMBLED, DEDUPED transcript for the skip check. This is
/// the single read path the design mandates: the producer decides whether a
/// unit already has a half exactly as every other consumer sees it, with
/// provenance already resolved, so a VALID peer half and an authentic half both
/// read as "this speaker has a half" and neither is re-produced.
typedef TranscriptReader = Future<CallTranscript> Function(String callKey);

/// Resolves a participant's `(l1, l2)` language pair. For the peer this is
/// `getPublicAnalyticsProfile(userId)` -> `(baseLanguage, targetLanguage)`; an
/// unresolved pair (either null) means the auto path does NOT transcribe that
/// half, leaving it to the on-demand language picker (task 3).
typedef PeerLanguageResolver =
    Future<({String? l1, String? l2})> Function(String userId);

/// Transcribes downloaded recording [bytes] in the [l1]/[l2] pair, placing the
/// utterances on [startedAtMs] .. [startedAtMs] + [durationMs]. The real one is
/// `transcribeRecordingWav` (recording_transcription.dart) bound to the app's
/// speech-to-text route; tests inject canned segments.
typedef RecordingTranscriber =
    Future<List<TranscriptSegment>> Function(
      Uint8List bytes, {
      required String l1,
      required String l2,
      required int startedAtMs,
      required int durationMs,
    });

/// Posts one peer-produced half. The real one is `writeCallTranscript` with the
/// invoking user as the writer and these fields carried through; tests record
/// the call. [spokenBy] is the speaker (the peer), [sourceAudioEventId] the
/// peer's own recording (the provenance anchor), [deviceId] the peer's recording
/// device (so the produced half keys under the same unit the peer's own half
/// would), and [langCode] the language it was transcribed in.
typedef PeerHalfPoster =
    Future<void> Function({
      required String callKey,
      required String spokenBy,
      required String sourceAudioEventId,
      required String? deviceId,
      required String? langCode,
      required ClockAnchor? clockAnchor,
      required List<TranscriptSegment> segments,
    });

/// The outcome of an on-demand peer-half transcription
/// ([WholeCallTranscriber.transcribeHalfOnDemand]).
///
/// A plain bool conflated the several distinct reasons a request did not post a
/// half, and the reader UI read EVERY false as "the saved audio is unusable" --
/// a terminal note over conditions that were often transient (no manifest yet)
/// or unrelated (a half already present, the gate not satisfied). Each outcome
/// here names what actually happened, so the view marks a half unavailable ONLY
/// when the audio itself is the problem and leaves the button retryable
/// otherwise.
enum OnDemandTranscriptionResult {
  /// A half was transcribed and posted. The view re-reads to show it.
  produced,

  /// A half for this speaker is already present -- an authentic half, or a valid
  /// peer-produced one that landed before or during this attempt -- so none was
  /// produced. The view re-reads to show the half that is already there.
  alreadyPresent,

  /// No audio manifest is visible yet (the peer's merge may still be in flight).
  /// TRANSIENT: the view leaves the button retryable.
  manifestPending,

  /// The resolved manifest names no recording for this speaker. The view leaves
  /// the button retryable rather than marking the half unavailable.
  noRecording,

  /// A recording was found but its audio is unusable for good -- a malformed
  /// url, empty bytes, or speech-to-text that produced nothing. TERMINAL for
  /// this screen: the view marks the half "audio unavailable" and does not offer
  /// the button again. A TRANSIENT download failure is [downloadFailed], not
  /// this.
  audioUnavailable,

  /// The recording download failed transiently -- a network or homeserver error,
  /// not a malformed url or empty audio. TRANSIENT: the view leaves the button
  /// retryable, because the bytes may be there on the next attempt.
  downloadFailed,

  /// The feature is not enabled for this run -- the flag is off, the invoker's
  /// subscription lapsed, or the 1:1 identity is not established. The view
  /// leaves the button retryable: a later entry with the gate satisfied can
  /// still work.
  disabled,
}

/// Produces the whole-call transcript for the INVOKING user: transcribes the
/// OTHER participant's saved recording so a paying user reads BOTH halves (#8792).
///
/// Every side effect is an injected seam, so the whole thing is unit-tested with
/// no server and no widgets -- the same shape the foundation's `AudioEventFetcher`
/// seam takes. The invoker's OWN half is NOT this class's job: it is posted by
/// the ordinary call-end flow (`CallRecord`) before this runs, which is the
/// "post own half first" step and is why there is zero duplicate speech-to-text
/// of the invoker's own audio here. This class does the PEER backfill.
///
/// Gating, discovery, skip, sequencing, retry and the in-flight guard:
/// * GATED on [isEnabled] read AT RUN TIME (the `CALL_RECORDING_TRANSCRIPT` flag
///   AND the invoker's live subscription) -- never a call-time snapshot, so a
///   downgrade between call end and this running stops it.
/// * DISCOVERY via [discover] (the audio manifest), independent of the relations
///   paging cap.
/// * SKIP a unit whose speaker already has a half in the assembled transcript
///   (an authentic half, or a VALID peer-produced one).
/// * SEQUENCING: a staggered, jittered grace after call end (letting a peer who
///   is ALSO subscribed post their own authentic half first), then re-read and
///   backfill; on demand, straight to producing one named half.
/// * MERGE-ARRIVAL RETRY: if no manifest is visible at call end, retry discovery
///   a bounded number of times (the peer's merge may land late) before giving up
///   to the on-demand path.
/// * IN-FLIGHT GUARD: an in-memory lock per recording device, plus a re-check of
///   the skip predicate before speech-to-text AND before send, so one device is
///   never transcribed twice and a half that appeared meanwhile is not doubled.
class WholeCallTranscriber {
  /// The invoking account -- the writer of any half this produces, and the one
  /// recording this NEVER transcribes (that half is the ordinary flow's).
  final String selfUserId;

  /// The call's two members. A recording whose sender is not one of them is not
  /// this call's and is never transcribed; a `spokenBy` is only ever one of them.
  final Set<String> participants;

  /// The flag AND the invoker's LIVE subscription, read at run time on every
  /// entry and again before each retry -- no persisted snapshot.
  final bool Function() isEnabled;

  final ManifestDiscoverer discover;
  final TranscriptReader readTranscript;
  final CallAudioDownloader download;
  final RecordingTranscriber transcribe;
  final PeerLanguageResolver resolvePeerLanguages;
  final PeerHalfPoster post;

  /// The injectable clock the grace and retry backoff wait on. Real code passes
  /// `Future.delayed`; a test passes a fake so no wall-clock time passes.
  final Future<void> Function(Duration) wait;

  /// The base grace waited after call end before the first discovery, and the
  /// backoff between merge-arrival retries. Both are jittered by [_jitter] so a
  /// room's two subscribed clients do not stampede the same instant.
  final Duration grace;
  final Duration retryBackoff;

  /// How many times discovery is retried when no manifest is visible yet. Zero
  /// disables retry (one discovery attempt only).
  final int maxManifestRetries;

  /// Returns a fraction in [0, 1) added as jitter to [grace]/[retryBackoff].
  /// Injected so a test gets a deterministic wait; defaults to `Random`.
  final double Function() _jitter;

  /// The recording devices currently being transcribed by THIS instance, so a
  /// concurrent call-end and on-demand run (or two backfill passes) never
  /// transcribe one device twice. In-memory and per-instance by design -- a
  /// cross-device or cross-process duplicate is caught by the skip re-check and
  /// is benign (the deterministic transaction id collapses a duplicate event).
  final Set<String> _inFlight = {};

  WholeCallTranscriber({
    required this.selfUserId,
    required this.participants,
    required this.isEnabled,
    required this.discover,
    required this.readTranscript,
    required this.download,
    required this.transcribe,
    required this.resolvePeerLanguages,
    required this.post,
    required this.wait,
    this.grace = const Duration(seconds: 3),
    this.retryBackoff = const Duration(seconds: 5),
    this.maxManifestRetries = 4,
    double Function()? jitter,
  }) : _jitter = jitter ?? Random().nextDouble;

  /// Wires the production seams for [room], leaving the invoker-specific facts --
  /// whether they are subscribed, and how a peer's languages resolve -- as
  /// injected callbacks so this file needs no controller or widget import (they
  /// are supplied by the call-lifecycle wiring, which already holds them).
  ///
  /// [isSubscribed] is read at run time on every entry (never cached), and the
  /// whole thing is additionally gated on `CALL_RECORDING_TRANSCRIPT`. Discovery
  /// selects the participant-authored manifest with the greatest VALIDATED source
  /// coverage -- the same rule the reader's provenance selection uses -- so a
  /// produced half's source is in the manifest the reader will select, and
  /// resolves each source by direct id (not the relations page), independent of
  /// the paging cap. The peer half posts through `writeCallTranscript` with the
  /// invoker as the writer and a complete, coherent recording-based accounting.
  factory WholeCallTranscriber.forCall({
    required Room room,
    required ChunkTranscriber transcribe,
    required bool Function() isSubscribed,
    required PeerLanguageResolver peerLanguages,
  }) {
    final client = room.client;
    final self = client.userID ?? '';
    final peer = room.directChatMatrixID;
    final participants = <String>{
      if (self.isNotEmpty) self,
      if (peer != null && peer.isNotEmpty) peer,
    };
    final relations = relationsFetcherFor(client);
    final audioFetch = audioEventFetcherFor(room);
    final downloader = callAudioDownloaderFor(client);

    Future<WholeCallManifest> discover(String callKey) async {
      final merged = await fetchCallAudioMerged(
        fetch: relations,
        roomId: room.id,
        callKey: callKey,
      );
      // Select the manifest AND build its recordings through the SAME shared
      // function the reader's provenance uses, from ONE memoized resolver -- so
      // there is no second fetch to double-count or to transiently drop a
      // validated source (a transient during validation makes the selection
      // uncertain -> absent -> the merge-arrival retry re-runs).
      return discoverWholeCallManifest(
        mergedRecordings: merged,
        participants: participants,
        callKey: callKey,
        resolve: audioResolverFor(audioFetch, room.id),
      );
    }

    Future<CallTranscript> readTranscript(String callKey) =>
        fetchCallTranscript(
          fetch: relations,
          roomId: room.id,
          callKey: callKey,
          expectedSenders: participants.toList(),
          selfId: self,
          resolveProvenance: (candidates) async {
            final merged = await fetchCallAudioMerged(
              fetch: relations,
              roomId: room.id,
              callKey: callKey,
            );
            return resolveTranscriptProvenance(
              candidates: candidates,
              mergedRecordings: merged,
              participants: participants,
              callKey: callKey,
              roomId: room.id,
              fetch: audioFetch,
            );
          },
        );

    Future<List<TranscriptSegment>> transcribeBytes(
      Uint8List bytes, {
      required String l1,
      required String l2,
      required int startedAtMs,
      required int durationMs,
    }) => transcribeRecordingWav(
      bytes,
      startedAtMs: startedAtMs,
      durationMs: durationMs,
      transcribe: transcribe,
      l1: l1,
      l2: l2,
    );

    Future<void> postHalf({
      required String callKey,
      required String spokenBy,
      required String sourceAudioEventId,
      required String? deviceId,
      required String? langCode,
      required ClockAnchor? clockAnchor,
      required List<TranscriptSegment> segments,
    }) async {
      await writeCallTranscript(
        send: (content, txnId) => room.sendEvent(
          content,
          type: CallTranscriptContent.relType,
          txid: txnId,
        ),
        callKey: callKey,
        senderId: self,
        // The PEER's recording device, so the produced half keys under the same
        // unit the peer's own half would.
        deviceId: deviceId,
        spokenBy: spokenBy,
        sourceAudioEventId: sourceAudioEventId,
        segments: segments,
        // A complete recording-based transcription of the peer's half: one
        // recording captured and transcribed, no live-chunk gaps. Coherent by
        // `CallTranscriptContent.fromJson`'s own rules (words need a capture).
        chunksCaptured: 1,
        chunksTranscribed: 1,
        chunksLost: 0,
        chunksRefusedUnsubscribed: 0,
        chunksSuppressed: 0,
        chunksDiscarded: 0,
        keptSpans: const [],
        discardedSpans: const [],
        captureDroppedMs: 0,
        captureRefused: false,
        drainComplete: true,
        langCode: langCode,
        clockAnchor: clockAnchor,
        encrypted: room.encrypted,
      );
    }

    return WholeCallTranscriber(
      selfUserId: self,
      participants: participants,
      isEnabled: () => Environment.callRecordingTranscript && isSubscribed(),
      discover: discover,
      readTranscript: readTranscript,
      download: downloader,
      transcribe: transcribeBytes,
      resolvePeerLanguages: peerLanguages,
      post: postHalf,
      wait: (duration) => Future<void>.delayed(duration),
    );
  }

  /// Runs the auto path at call end: after the invoker's own half is posted by
  /// the ordinary flow, wait a jittered grace, then discover and backfill peer
  /// halves; retry discovery a bounded number of times if the manifest is not
  /// visible yet. A no-op the moment [isEnabled] is false, checked again before
  /// every retry so a mid-flight downgrade stops it.
  Future<void> transcribeAtCallEnd(String callKey) async {
    if (!isEnabled() || !_identityKnown) return;
    await wait(_jittered(grace));
    for (var attempt = 0; ; attempt++) {
      if (!isEnabled()) return;
      final manifest = await discover(callKey);
      if (manifest.resolved) {
        await _backfillPeers(callKey, manifest.recordings);
        return;
      }
      if (attempt >= maxManifestRetries) return;
      await wait(_jittered(retryBackoff));
    }
  }

  /// Transcribes ONE named peer half on demand (task 3's Transcribe button /
  /// language picker). Same skip and re-check rules as the auto path, with no
  /// grace: the user asked for it now. [language] overrides the resolved target
  /// language for the picker path, when the peer's own languages did not resolve.
  /// Returns an [OnDemandTranscriptionResult] naming the outcome, so the view
  /// marks a half "audio unavailable" only for [OnDemandTranscriptionResult
  /// .audioUnavailable] and leaves the button retryable for the transient and
  /// not-yet-possible outcomes.
  Future<OnDemandTranscriptionResult> transcribeHalfOnDemand({
    required String callKey,
    required String speakerId,
    String? language,
  }) async {
    if (!isEnabled() || !_identityKnown) {
      return OnDemandTranscriptionResult.disabled;
    }
    final manifest = await discover(callKey);
    if (!manifest.resolved) return OnDemandTranscriptionResult.manifestPending;
    final recording = _recordingForSpeaker(manifest.recordings, speakerId);
    if (recording == null) return OnDemandTranscriptionResult.noRecording;
    if (_skip(await readTranscript(callKey), speakerId)) {
      return OnDemandTranscriptionResult.alreadyPresent;
    }
    return _produceOnePeer(callKey, recording, chosenLanguage: language);
  }

  Future<void> _backfillPeers(
    String callKey,
    List<CallAudioRecording> recordings,
  ) async {
    final transcript = await readTranscript(callKey);
    for (final recording in recordings) {
      final speaker = recording.senderId;
      // The invoker's own recording is the ordinary flow's half, and a recording
      // whose sender is not on the call is not this call's -- neither is ever
      // transcribed as a peer half.
      if (speaker == selfUserId) continue;
      if (!participants.contains(speaker)) continue;
      // Skip a unit that already has a half on screen -- an authentic half (the
      // peer was subscribed and posted their own) or a VALID peer-produced one
      // (another subscriber already backfilled it). Both read the deduped output.
      if (_skip(transcript, speaker)) continue;
      await _produceOnePeer(callKey, recording);
    }
  }

  /// Produces one peer half, returning an [OnDemandTranscriptionResult] that
  /// names why when it did not (the auto path ignores it; the on-demand path
  /// maps it to a UI state). Acquires the in-flight lock synchronously (no await
  /// between the check and the add), then re-checks the skip predicate against a
  /// FRESH read before speech-to-text and again before send.
  Future<OnDemandTranscriptionResult> _produceOnePeer(
    String callKey,
    CallAudioRecording recording, {
    String? chosenLanguage,
  }) async {
    final speaker = recording.senderId;
    // Defensive: both callers already exclude self and non-participants, so this
    // is unreached in practice -- reported as no-recording so the view never
    // marks such a half unavailable off a guard that cannot fire.
    if (speaker == selfUserId) return OnDemandTranscriptionResult.noRecording;
    if (!participants.contains(speaker)) {
      return OnDemandTranscriptionResult.noRecording;
    }

    final device = recording.content.deviceId ?? '';
    // Check-and-add is atomic: there is no await between them, so two concurrent
    // runs for one device cannot both pass. A concurrent pass holding the lock
    // means a half for this exact unit is already being written, so this reads
    // as already-present: the view re-reads rather than marking it unavailable.
    if (_inFlight.contains(device)) {
      return OnDemandTranscriptionResult.alreadyPresent;
    }
    _inFlight.add(device);
    try {
      final resolved = await resolvePeerLanguages(speaker);
      // The target language drives the whole provider chain, so it must be the
      // SPEAKER's -- the peer's resolved target, or the picker's explicit choice.
      final l2 = chosenLanguage ?? resolved.l2;
      // The base language is the peer's, falling back to the picker's choice only
      // so the request has a pair at all when the peer's profile did not resolve.
      final l1 = resolved.l1 ?? chosenLanguage;
      // Unresolved with no picker choice: NO auto-produce and no silent fallback
      // -- the on-demand language picker (task 3) is the recovery, so this stays
      // retryable rather than terminal. (Unreached on the on-demand path, which
      // resolves the language before calling; the auto path discards the result.)
      if (l1 == null || l2 == null) return OnDemandTranscriptionResult.disabled;

      // Re-read before spending speech-to-text: the transcript that gated this
      // in [_backfillPeers] may be stale, and a peer authentic half or another
      // subscriber's valid half may have landed since.
      if (_skip(await readTranscript(callKey), speaker)) {
        return OnDemandTranscriptionResult.alreadyPresent;
      }

      final Uint8List? bytes;
      try {
        bytes = await _download(recording);
      } catch (_) {
        // A transient download failure (_download rethrows those; a malformed
        // url comes back null below). Retryable, not terminal.
        return OnDemandTranscriptionResult.downloadFailed;
      }
      if (bytes == null || bytes.isEmpty) {
        return OnDemandTranscriptionResult.audioUnavailable;
      }

      final segments = await transcribe(
        bytes,
        l1: l1,
        l2: l2,
        startedAtMs: _peerStartMs(recording),
        durationMs: recording.content.durationMs,
      );
      // An empty transcription is NOT posted as "the peer said nothing": a
      // subscriber's speech-to-text miss must not put that claim in the peer's
      // mouth. The unit stays absent, and the on-demand button remains. The
      // audio was there but yielded nothing usable, so this reads as unavailable.
      if (segments.isEmpty) return OnDemandTranscriptionResult.audioUnavailable;

      // Re-check once more before sending: STT is the slow step, and a half may
      // have landed while it ran.
      if (_skip(await readTranscript(callKey), speaker)) {
        return OnDemandTranscriptionResult.alreadyPresent;
      }

      await post(
        callKey: callKey,
        spokenBy: speaker,
        sourceAudioEventId: recording.eventId,
        deviceId: recording.content.deviceId,
        langCode: l2,
        clockAnchor: recording.content.clockAnchor,
        segments: segments,
      );
      return OnDemandTranscriptionResult.produced;
    } finally {
      _inFlight.remove(device);
    }
  }

  /// Whether [speaker] already has a half in the assembled transcript. A half
  /// that resolved to words or an empty-but-present authentic half both count;
  /// only a truly absent speaker (no half, or one held out as pending/invalid)
  /// is produced. This is the union of the two skip predicates -- an authentic
  /// half and a VALID peer half both attribute to [speaker] here, and a 1:1 DM
  /// has one recording per unit, so the speaker key IS the unit key.
  bool _skip(CallTranscript transcript, String speaker) =>
      transcript.halves.any(
        (half) => half.senderId == speaker && half.state != HalfState.absent,
      );

  /// Both participants of the 1:1 DM are known. A half is signed by [selfUserId]
  /// (the writer) and keyed by a unit that needs exactly two members; an empty
  /// self, or a participant set that is not exactly two, means the identity is
  /// not established, so nothing is produced -- the writer and the txn lane must
  /// never be empty, and a `spokenBy` must be a real participant.
  bool get _identityKnown => selfUserId.isNotEmpty && participants.length == 2;

  CallAudioRecording? _recordingForSpeaker(
    List<CallAudioRecording> recordings,
    String speaker,
  ) {
    for (final recording in recordings) {
      if (recording.senderId == speaker) return recording;
    }
    return null;
  }

  /// Where the peer's recording began on the PEER's own device clock, so the
  /// produced half's utterances land on the peer's clock exactly as if the peer
  /// had transcribed it -- the reader's per-half clock correction then carries
  /// them onto the shared clock.
  ///
  /// When the recording carried no anchor/offset the device clock is unknown,
  /// so this approximates the start from the recording event's WALL clock -- its
  /// server-receive time less its duration -- rather than epoch (0). Zero would
  /// stamp every unanchored peer turn at ~1970, and the reader orders by `atMs`
  /// even where it withholds printed times, so all peer turns would sort before
  /// all of the invoker's own turns. Clamped at 0 so a duration longer than the
  /// elapsed wall time never yields a negative start.
  ///
  /// This estimate assumes the recording was uploaded promptly: a long upload
  /// delay between the real start and the server-receive time pushes it late.
  /// The anchored path above is the accurate one; this is only the fallback the
  /// reader already tolerated, so an approximate placement is acceptable here.
  int _peerStartMs(CallAudioRecording recording) {
    final anchor = recording.content.clockAnchor;
    final offset = recording.content.recordingStartedOffsetFromDeviceJoinMs;
    if (anchor != null && offset != null) return anchor.deviceMs + offset;
    final end = recording.originServerTs.millisecondsSinceEpoch;
    // A non-positive or missing duration cannot bound the start, so fall back to
    // the receive time itself rather than adding a negative (which would place
    // the start in the future). A positive duration is subtracted and the result
    // is clamped so it is never negative.
    final durationMs = recording.content.durationMs;
    final start = durationMs > 0 ? end - durationMs : end;
    return start < 0 ? 0 : start;
  }

  Future<Uint8List?> _download(CallAudioRecording recording) async {
    final Uri uri;
    try {
      uri = Uri.parse(recording.content.url);
    } catch (e, s) {
      Logs().w(
        'A peer call recording url could not be parsed; not transcribed',
        e,
        s,
      );
      return null;
    }
    try {
      return await download(uri);
    } on ArgumentError catch (e, s) {
      // A malformed mxc:// url (mxcServerAndMediaId rejects it) can never
      // download -- terminal, like the unparseable url above. Null here maps to
      // audioUnavailable.
      Logs().w(
        'A peer call recording url could not be used; not transcribed',
        e,
        s,
      );
      return null;
    } catch (e, s) {
      // A transient failure (network or homeserver). RETHROWN so the caller can
      // keep the retry offered instead of marking the half permanently
      // unavailable -- the bytes may be there on the next attempt.
      Logs().w(
        'A peer call recording download failed; it can be retried',
        e,
        s,
      );
      rethrow;
    }
  }

  Duration _jittered(Duration base) =>
      base + Duration(microseconds: (base.inMicroseconds * _jitter()).round());
}
