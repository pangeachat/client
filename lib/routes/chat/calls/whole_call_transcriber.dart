import 'dart:math';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_download.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
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
      final manifests = [
        for (final m in merged)
          if (participants.contains(m.senderId) && m.content.callKey == callKey)
            m,
      ];
      if (manifests.isEmpty) return WholeCallManifest.absent;

      // One direct fetch per source id, memoized across validation and the
      // final resolve, so a source is fetched at most once whatever how many
      // manifests reference it.
      final cache = <String, CallAudioRecording?>{};
      Future<CallAudioRecording?> resolve(String id) async {
        if (cache.containsKey(id)) return cache[id];
        CallAudioRecording? recording;
        try {
          final event = await room.getEventById(id);
          if (event != null &&
              !event.redacted &&
              event.type == CallAudioContent.relType) {
            final content = CallAudioContent.fromJson(event.content);
            // A validated unit: a participant's own recording for THIS call,
            // with a device -- the unit a half keys by. Anything else lends the
            // manifest no coverage and yields no recording.
            if (content != null &&
                content.callKey == callKey &&
                content.deviceId != null &&
                participants.contains(event.senderId)) {
              recording = CallAudioRecording(
                eventId: event.eventId,
                senderId: event.senderId,
                originServerTs: event.originServerTs,
                content: content,
              );
            }
          }
        } catch (_) {
          // Transient/gone this pass -- not validated; a retry re-fetches.
          recording = null;
        }
        cache[id] = recording;
        return recording;
      }

      CallAudioMergedRecording? best;
      var bestCount = 0;
      for (final manifest in manifests) {
        var count = 0;
        for (final id in manifest.content.sourceEventIds.toSet()) {
          if (await resolve(id) != null) count++;
        }
        if (count > bestCount) {
          best = manifest;
          bestCount = count;
        }
      }
      // No manifest validates anything yet -- the merge may still be in flight.
      if (best == null || bestCount == 0) return WholeCallManifest.absent;

      final recordings = <CallAudioRecording>[];
      for (final id in best.content.sourceEventIds.toSet()) {
        final recording = await resolve(id);
        if (recording != null) recordings.add(recording);
      }
      return WholeCallManifest(resolved: true, recordings: recordings);
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
    if (!isEnabled()) return;
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
  /// Returns whether a half was produced.
  Future<bool> transcribeHalfOnDemand({
    required String callKey,
    required String speakerId,
    String? language,
  }) async {
    if (!isEnabled()) return false;
    final manifest = await discover(callKey);
    if (!manifest.resolved) return false;
    final recording = _recordingForSpeaker(manifest.recordings, speakerId);
    if (recording == null) return false;
    if (_skip(await readTranscript(callKey), speakerId)) return false;
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

  /// Produces one peer half, or returns false when a skip/guard/language/bytes
  /// condition means it should not. Acquires the in-flight lock synchronously
  /// (no await between the check and the add), then re-checks the skip predicate
  /// against a FRESH read before speech-to-text and again before send.
  Future<bool> _produceOnePeer(
    String callKey,
    CallAudioRecording recording, {
    String? chosenLanguage,
  }) async {
    final speaker = recording.senderId;
    if (speaker == selfUserId) return false;
    if (!participants.contains(speaker)) return false;

    final device = recording.content.deviceId ?? '';
    // Check-and-add is atomic: there is no await between them, so two concurrent
    // runs for one device cannot both pass.
    if (_inFlight.contains(device)) return false;
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
      // -- the on-demand language picker (task 3) is the recovery.
      if (l1 == null || l2 == null) return false;

      // Re-read before spending speech-to-text: the transcript that gated this
      // in [_backfillPeers] may be stale, and a peer authentic half or another
      // subscriber's valid half may have landed since.
      if (_skip(await readTranscript(callKey), speaker)) return false;

      final bytes = await _download(recording);
      if (bytes == null || bytes.isEmpty) return false;

      final segments = await transcribe(
        bytes,
        l1: l1,
        l2: l2,
        startedAtMs: _peerStartMs(recording),
        durationMs: recording.content.durationMs,
      );
      // An empty transcription is NOT posted as "the peer said nothing": a
      // subscriber's speech-to-text miss must not put that claim in the peer's
      // mouth. The unit stays absent, and the on-demand button remains.
      if (segments.isEmpty) return false;

      // Re-check once more before sending: STT is the slow step, and a half may
      // have landed while it ran.
      if (_skip(await readTranscript(callKey), speaker)) return false;

      await post(
        callKey: callKey,
        spokenBy: speaker,
        sourceAudioEventId: recording.eventId,
        deviceId: recording.content.deviceId,
        langCode: l2,
        clockAnchor: recording.content.clockAnchor,
        segments: segments,
      );
      return true;
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
  /// them onto the shared clock. Zero (uncorrected) when the peer's recording
  /// carried no anchor/offset, which the reader tolerates.
  int _peerStartMs(CallAudioRecording recording) {
    final anchor = recording.content.clockAnchor;
    final offset = recording.content.recordingStartedOffsetFromDeviceJoinMs;
    if (anchor != null && offset != null) return anchor.deviceMs + offset;
    return 0;
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
    } catch (e, s) {
      // Terminal for this pass, not a fallback to the writer: the bytes are the
      // ground truth, and without them there is nothing honest to transcribe.
      Logs().w(
        'A peer call recording could not be downloaded; not transcribed',
        e,
        s,
      );
      return null;
    }
  }

  Duration _jittered(Duration base) =>
      base + Duration(microseconds: (base.inMicroseconds * _jitter()).round());
}
