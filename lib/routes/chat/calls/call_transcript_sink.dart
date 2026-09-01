import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_upload_gate.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/calls/speech_trim.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/audio_encoding_enum.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_request_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// Transcribes a chunk. Injected so the sink can be driven without the network,
/// and because the route is billed per call — a test that reached it would spend
/// money to assert something it can assert for free.
typedef ChunkTranscriber =
    Future<SpeechToTextResponseModel> Function(SpeechToTextRequestModel);

/// Turns a call's captured audio into speaking analytics.
///
/// Each chunk goes through the same route a voice message does, and its result
/// is kept exactly as it came back. Nothing is re-transcribed: the provider
/// chain is a ranked fallback, so running it twice over the same audio can
/// return a different transcript, and a speaker's credit would then be able to
/// go *down* when a late chunk arrived. Freezing each result makes the total the
/// union of the parts, which can only grow.
class CallTranscriptSink implements CallAudioSink {
  final ChunkTranscriber transcribe;

  /// The speaker's languages, captured once when the call starts.
  ///
  /// Read at t0 rather than per chunk: a learner who changes their target
  /// language mid-call would otherwise have one call transcribed against two
  /// different languages, and the halves would disagree.
  final String userL1;
  final String userL2;

  /// Keyed by chunk index rather than appended.
  ///
  /// Deliveries deliberately overlap — the recorder hands each chunk over as it
  /// completes and does not wait — so a later chunk can come back from the
  /// provider first. Appending would order the call by provider latency rather
  /// than by when the learner spoke.
  final Map<int, SpeechToTextResponseModel> _byIndex = {};

  /// Where each chunk's audio sat, keyed the same way [_byIndex] is.
  ///
  /// BESIDE it, never wrapped into it. `_byIndex` also feeds [transcripts],
  /// [hasTranscript], [chunksTranscribed], [constructs] and [langCode], and
  /// wrapping its value in a record would make every one of those unwrap
  /// something it does not care about — which either fails to compile or,
  /// worse, quietly miscounts.
  ///
  /// Recorded when the chunk is handed over rather than when its transcription
  /// comes back, so a chunk that FAILED has a position with no response beside
  /// it. That is the case the pairing below exists to survive.
  ///
  /// The DURATION is here because the positioning rule bounds a chunk's word
  /// timings by it, and it lives only on [PcmChunk]. Keeping the start time
  /// alone would throw the ceiling away.
  final Map<int, ({int startedAtMs, int durationMs})> _placements = {};

  final Set<int> _transcribed = {};

  /// Each chunk's uses, built once and kept. See [constructs].
  final Map<int, List<OneConstructUse>> _usesByIndex = {};

  /// What [_usesByIndex] was built against. Different anchors are a different
  /// batch, so the old one is discarded rather than mixed with the new.
  ({String roomId, String eventId})? _anchor;

  /// How a chunk's audio is narrowed to the part somebody spoke.
  ///
  /// Injectable because every number in it is calibrated against a single
  /// recording, and a test that could not move them could not show what any of
  /// them is holding up.
  final SpeechTrimSettings trimSettings;

  /// What bounds this DEVICE's uploads to the choreographer, across every call
  /// and every account signed in on it.
  ///
  /// Shared by default, because that is the only scope at which "how much is
  /// this device sending" is a real question — a gate per sink would be a gate
  /// per call and would cap nothing. Injectable so a test gets its own.
  final CallUploadGate gate;

  CallTranscriptSink({
    required this.transcribe,
    required this.userL1,
    required this.userL2,
    this.settleWithin = defaultSettleWithin,
    this.trimSettings = const SpeechTrimSettings(),
    CallUploadGate? gate,
  }) : gate = gate ?? CallUploadGate.shared;

  /// What was said, in the order it was said, skipping chunks that produced
  /// nothing readable.
  ///
  /// Strings rather than the provider's response objects. Those are mutable all
  /// the way down — the response holds mutable lists of transcripts holding
  /// mutable lists of tokens — so handing them out would let any caller empty
  /// one and change what this call is worth. Nothing outside needs them; text is
  /// what a transcript view or a log actually wants.
  List<String> get transcripts => [
    for (final result in _ordered)
      if (result.hasUsableTranscript) result.transcript.text,
  ];

  /// What was said, cut into readable utterances.
  ///
  /// Built here rather than by handing out the frozen responses, for the same
  /// reason [transcripts] returns strings: those responses are mutable all the
  /// way down, so passing them out would let any caller empty one and change
  /// what this call is worth.
  ///
  /// The one path that pairs a response with where its audio sat. It walks
  /// [_byIndex] sorted by key and looks the placement up BY THAT SAME KEY,
  /// never by zipping two sorted lists: a chunk whose transcription FAILED is
  /// recorded in [_failed] and never reaches `_byIndex`, so its placement has
  /// no response beside it — and a positional zip would then slide every later
  /// chunk's start time onto the wrong words.
  List<TranscriptSegment> get segments => buildSegments([
    for (final index in _byIndex.keys.toList()..sort())
      TranscribedChunk(
        result: _byIndex[index]!,
        // Non-null by construction: a placement is written before the request
        // that fills `_byIndex` is even issued, so nothing can be in one map
        // and missing from the other.
        startedAtMs: _placements[index]!.startedAtMs,
        durationMs: _placements[index]!.durationMs,
      ),
  ]);

  /// Whether [close] settled everything it still had in flight.
  ///
  /// Optimistic until [close] runs, because nothing has been abandoned before
  /// then. FALSE afterwards means work was given up on, so what this sink holds
  /// is knowingly short of what was said -- and the half published from it has
  /// to say so.
  bool get drainComplete => _drainComplete;
  bool _drainComplete = true;

  /// How many chunks came back, readable or not. The count is what a caller can
  /// have without a handle on anything mutable.
  int get chunkCount => _byIndex.length;

  List<SpeechToTextResponseModel> get _ordered => [
    for (final index in _byIndex.keys.toList()..sort()) _byIndex[index]!,
  ];

  /// Whether anything was said that speech-to-text could read.
  ///
  /// A 200 carrying no results, or an empty nested transcript, is a real answer:
  /// the provider chain ran and found nothing sayable. Reading such a response's
  /// transcript throws, so this asks the model's own gate rather than merely
  /// noting that a response arrived.
  bool get hasTranscript => _byIndex.values.any((r) => r.hasUsableTranscript);

  @override
  Future<void> deliver(PcmChunk chunk, {Duration? within}) {
    // A redelivery of a chunk still being transcribed joins that work rather
    // than returning as though it were finished. The caller gives each attempt a
    // limit and retries; without this, the retry reported success while the
    // first attempt was still running, and the call's words could be read before
    // it landed.
    final running = _running[chunk.index];
    if (running != null) return running;

    // A chunk already found to hold no speech is not analysed a second time.
    // Checked ahead of `_transcribed` because the two are different answers:
    // this one was never sent, and re-deciding it would cost the analysis again
    // and risk counting it in two places.
    if (_suppressed.contains(chunk.index)) return Future.value();

    // A chunk is transcribed once. Redelivery — a retry, or a hangup racing a
    // flush — must not bill the route again or count the same words twice.
    if (!_transcribed.add(chunk.index)) return Future.value();
    // A retry of a previously failed chunk is no longer a loss.
    _failed.remove(chunk.index);

    // A block, not an arrow. Removing from the map RETURNS the future being
    // removed, and whenComplete waits for a future its callback returns — so
    // the arrow form makes this future wait for itself and it never completes.
    final work = _transcribeChunk(chunk, within).whenComplete(() {
      _running.remove(chunk.index);
    });
    _running[chunk.index] = work;
    return work;
  }

  @override
  void discarded(PcmChunk chunk) {
    // Recorded by INDEX, like every other set here, so a chunk that somehow
    // arrived twice counts once. Disjoint from the rest by construction: the
    // recorder sets a chunk aside instead of delivering it, so a discarded
    // index never reaches [deliver] and cannot also be transcribed, failed or
    // suppressed.
    _discarded.add(chunk.index);
  }

  /// Transcriptions still running, by chunk. Closing waits for these: the words
  /// are read the moment the call is over, and one still in flight would be
  /// missing from them.
  final Map<int, Future<void>> _running = {};

  Future<void> _transcribeChunk(PcmChunk chunk, Duration? within) async {
    // Narrowed to the part somebody spoke, BEFORE anything is recorded about
    // it. A device records its own microphone for the whole call, so while the
    // other person talks it captures its own noise floor -- and a chunk that is
    // mostly noise does not merely waste a request. Measured on a real 40.4s
    // chunk, sending it whole returned three words where its speech alone
    // returned forty-seven, and both providers invented words for the silence.
    //
    // Costs about 13ms for a 40-second chunk, once per chunk, so it runs here
    // rather than on an isolate of its own.
    //
    // INSIDE the failure accounting, not in front of it. Reading the audio is
    // work that can throw — it walks the chunk's bytes — and outside the catch
    // a throw here left the index claimed in `_transcribed` with nothing to
    // release it: every retry then found the index taken and returned as though
    // it had succeeded, and the half published the chunk as captured, not
    // transcribed and not lost, which is exactly how a chunk the PROVIDER read
    // as silence looks. Speech this device dropped would have been indis-
    // tinguishable from speech nobody spoke.
    final TrimmedChunkAudio? audio;
    try {
      audio = trimToSpeech(chunk, settings: trimSettings);
    } catch (e, s) {
      _transcribed.remove(chunk.index);
      _failed.add(chunk.index);
      Logs().w('Could not read call chunk ${chunk.index}', e, s);
      rethrow;
    }
    if (audio == null) {
      // Captured, and held nothing said. Not a failure and not a loss: the
      // audio was examined and found empty, so there is nothing to retry and
      // nothing to send. It is counted apart from both because THIS DEVICE
      // decided it, using a detector calibrated on one recording -- a weaker
      // claim than a provider reading a chunk as silence, and a reader is
      // entitled to see the difference.
      _transcribed.remove(chunk.index);
      _suppressed.add(chunk.index);
      return;
    }

    // Recorded from the audio ACTUALLY SENT, before the request goes out. It is
    // the only moment the audio's own timing is visible here at all: what comes
    // back is a transcript, which knows nothing about when the samples were
    // captured.
    //
    // Both halves shift together. The start moves forward by however much of
    // the chunk was dropped, so a word's timing still names the moment it was
    // spoken; and the duration describes the audio the provider was given
    // rather than the chunk it came from, which is the ceiling those timings
    // are checked against.
    _placements[chunk.index] = (
      startedAtMs: chunk.startedAtMs + audio.startMs,
      durationMs: audio.durationMs,
    );
    final request = SpeechToTextRequestModel(
      audioContent: audio.wav,
      // Timings AS WELL AS tokens. `skipTokenize` would buy the timings by
      // giving up `stt_tokens`, and `constructs()` is gated on those --
      // the credit would silently go to zero on every call.
      includeWordTimings: true,
      config: SpeechToTextAudioConfigModel(
        encoding: AudioEncodingEnum.linear16,
        sampleRateHertz: chunk.sampleRate,
        userL1: userL1,
        userL2: userL2,
      ),
    );
    try {
      // Through the gate, which bounds how many of these this device has out at
      // once and stops it hammering a choreographer that is already failing.
      // Only the REQUEST goes through it: the trim above is CPU work of about
      // thirteen milliseconds, and letting it hold a permit would cap the wrong
      // thing.
      //
      // Bounded here, where the request is, so that giving up on it is a
      // failure of the attempt: the index is released below and the next
      // attempt can try again. Bounded by the waiter instead, the abandoned one
      // stayed listed as in flight HERE and every retry waited on it again —
      // three attempts that were only ever one.
      //
      // Only as far as this sink, mind. In production `transcribe` reaches
      // `SpeechToTextRepo`, which dedupes by the audio's digest for as long as
      // its own sixty-second fetch is in flight — so a retry issued while the
      // first request is still running joins that request rather than making a
      // second one. That is the repo's decision, not this one's, and it is why
      // this comment no longer claims the retry is always a fresh upload.
      //
      // The budget covers the WAITING too. A chunk refused by the gate for its
      // whole budget is a chunk this device captured and could not send, and it
      // falls into the same accounting as any other failure below — recorded as
      // LOST, never as suppressed, which would claim we had looked at the audio
      // and found nothing said.
      _byIndex[chunk.index] = await gate.run(
        () => transcribe(request),
        within: within,
      );
    } catch (e, s) {
      // Released and re-thrown, so the caller's retry can try again. Swallowing
      // this reported success to a caller whose whole purpose is to retry, and
      // one bad moment from the provider cost that chunk's words for good.
      //
      // The index is only kept once there is something to keep: a chunk that
      // was transcribed must never be transcribed twice, but one that was not
      // has nothing to double-count.
      _transcribed.remove(chunk.index);
      // Remembered, not just logged. A chunk that failed and was never retried
      // is speech this device captured and lost, and the half it belongs to has
      // to say so rather than present the rest as the whole.
      _failed.add(chunk.index);
      Logs().w('Could not transcribe call chunk ${chunk.index}', e, s);
      rethrow;
    }
  }

  /// How long closing waits for transcriptions still running.
  ///
  /// They carry their own limits, so this only exists so that a stuck one cannot
  /// hold the end of a call open for ever.
  ///
  /// Injectable because the abandoned-drain path is what `drainComplete`
  /// exists to report, and at sixty seconds no test could reach it -- so the
  /// field guarding against a half falsely claiming completeness was itself
  /// uncovered.
  final Duration settleWithin;
  static const defaultSettleWithin = Duration(seconds: 60);

  @override
  Future<bool> close() async {
    // Waited for, not abandoned. The call's words are read as soon as this
    // returns, and a transcription still running would simply be missing from
    // them — the learner would lose that stretch with nothing to show why.
    //
    // One chunk failing is not a reason to stop waiting for the others. Each
    // failure is already logged where it happens and releases its index for a
    // retry, so it arrives here as an error on a future -- and letting that
    // out of the wait ended the loop below, which is the only thing watching
    // for a retry that started while we waited.
    //
    // The budget is for the whole close, not for each turn of the loop: a
    // chunk that keeps failing and keeps being retried would otherwise hold
    // the end of a call open a minute at a time, for as long as it kept
    // failing.
    final deadline = DateTime.now().add(settleWithin);
    while (_running.isNotEmpty) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        Logs().w(
          'Gave up waiting for a call transcription; its words are lost',
        );
        return _drainComplete = false;
      }
      try {
        await Future.wait(
          List.of(_running.values).map((work) => work.catchError((_) {})),
        ).timeout(left);
      } on TimeoutException {
        Logs().w(
          'Gave up waiting for a call transcription; its words are lost',
        );
        return _drainComplete = false;
      }
    }
    return _drainComplete = true;
  }

  /// How many chunks this device captured, whatever became of them.
  ///
  /// The denominator of the completeness accounting: compared against
  /// [chunksTranscribed], it is what lets a reader see that a stretch of speech
  /// was captured and then lost, rather than never spoken.
  ///
  /// Counts the SUPPRESSED chunks too, and the DISCARDED ones. Both of the
  /// other counts are only written inside `deliver()`, so a chunk this device
  /// chose not to send used to vanish from the denominator entirely -- the one
  /// number that is supposed to say "this much audio existed" quietly
  /// forgetting the audio nobody ever saw. A discarded chunk existed exactly as
  /// a suppressed one did, and leaving it out would repeat that mistake for the
  /// one decision in this feature that destroys audio outright.
  int get chunksCaptured =>
      _transcribed.length +
      _failed.length +
      _suppressed.length +
      _discarded.length;

  /// How many chunks came back with something readable in them.
  int get chunksTranscribed =>
      _byIndex.values.where((r) => r.hasUsableTranscript).length;

  /// Chunks this device captured and then LOST -- transcription failed and was
  /// never retried.
  ///
  /// The number that actually means a gap. It is tempting to infer one from
  /// `chunksTranscribed < chunksCaptured`, and that was wrong: those two count
  /// different things. A chunk the provider read as SILENCE is captured and not
  /// transcribed, yet nothing was dropped -- the audio was processed and found
  /// to contain nothing said. Almost every real call has a quiet stretch, so
  /// inferring loss from the difference marked nearly every transcript
  /// incomplete, which leaves the flag meaning nothing when it matters.
  int get chunksLost => _failed.length;

  /// Chunks whose transcription failed outright and was never retried.
  final Set<int> _failed = {};

  /// Chunks this device captured, examined, and found to hold no speech.
  ///
  /// Deliberately NOT counted in [chunksLost]. Nothing was dropped: the audio
  /// was read and there was nothing in it. Almost every real call has a quiet
  /// stretch, so treating this as a gap would mark nearly every transcript
  /// incomplete and leave the flag meaning nothing when it matters -- the same
  /// reasoning already recorded on [chunksLost].
  ///
  /// It is published all the same, because it is a claim by THIS DEVICE rather
  /// than by a provider, and a reader that wants to distrust our judgement
  /// needs the number to do it with.
  int get chunksSuppressed => _suppressed.length;
  final Set<int> _suppressed = {};

  /// Chunks this device captured and deliberately did not send, because
  /// another of this account's devices was recording the same stretch.
  ///
  /// Deliberately NOT counted in [chunksLost], and for a different reason from
  /// [chunksSuppressed]: a correct discard loses nothing at all, because the
  /// words are in the sibling's half. Calling it a gap would mark a transcript
  /// incomplete over audio that is present, one event away.
  ///
  /// It is published because a discard rests entirely on a claim about ANOTHER
  /// device, and nothing in this half can check that claim. Chunk indices do
  /// not line up across devices -- each numbers its own -- so what this affords
  /// is not a lookup but a QUESTION worth asking: this half says a stretch was
  /// set aside, and the sibling's half is where that speech has to be. A
  /// discard that was wrong leaves it in neither. Without the count nobody
  /// knows there is anything to look for.
  int get chunksDiscarded => _discarded.length;
  final Set<int> _discarded = {};

  /// The call's speaking analytics, as one batch.
  ///
  /// Built at the end rather than per chunk because the constructs are anchored
  /// to the call's timeline event, and that event does not exist until the call
  /// does.
  ///
  /// **Each chunk's uses are built once and kept.** A use is stamped with the
  /// moment it was made, so rebuilding one would produce a use that differs from
  /// the one already recorded. Caching the whole batch instead would have the
  /// opposite problem: a chunk that arrived after the batch was read would be
  /// silently dropped.
  ///
  /// Per-chunk is what satisfies both. Existing uses never change, and a late
  /// chunk adds its own — which is the monotonicity this design rests on,
  /// expressed in the code rather than only in the comment.
  List<OneConstructUse> constructs({
    required String roomId,
    required String eventId,
  }) {
    if (_anchor?.roomId != roomId || _anchor?.eventId != eventId) {
      _usesByIndex.clear();
      _anchor = (roomId: roomId, eventId: eventId);
    }
    return List<OneConstructUse>.unmodifiable([
      for (final index in _byIndex.keys.toList()..sort())
        ..._usesByIndex
            .putIfAbsent(index, () {
              final result = _byIndex[index]!;
              return result.hasUsableTokens
                  ? result.constructs(roomId, eventId, ConstructUseTypeEnum.pvc)
                  : const [];
            })
            .map(_copyOf),
    ]);
  }

  /// A use is a mutable object, so handing out the cached one would let any
  /// caller change what a later read returns — including the timestamp the
  /// freezing exists to hold still. Callers get their own; the recorded values
  /// stay the recorded values.
  static OneConstructUse _copyOf(OneConstructUse use) => OneConstructUse(
    useType: use.useType,
    lemma: use.lemma,
    constructType: use.constructType,
    metadata: use.metadata,
    category: use.category,
    form: use.form,
    xp: use.xp,
    id: use.id,
  );

  /// The longest a language tag may be before we stop believing it.
  ///
  /// A BCP 47 primary subtag is at most 8 characters. This is the ceiling on a
  /// value that arrives from a speech provider and goes straight into an event
  /// with a hard size limit, so it is a bound on untrusted input rather than a
  /// formatting preference.
  static const maxLangCodeLength = 8;

  /// The language the call was transcribed in, or null if nothing was.
  ///
  /// Taken from the first chunk that produced anything: the speaker's target
  /// language is pinned for the whole call, so every chunk agrees and the
  /// earliest answer is the call's answer.
  ///
  /// Bounded, because this is a provider's word and it is the only unbounded
  /// field in the event. Splitting on a hyphen trims `es-MX` to `es` but does
  /// nothing at all to a value with no hyphen in it, so a malformed answer
  /// could carry an arbitrary amount of text into a half that is packed to fit
  /// a byte ceiling. Anything past the ceiling is not a language tag, so it is
  /// dropped rather than truncated into a different, plausible-looking one.
  ///
  /// Empty is dropped for the same reason. The response model reads an
  /// unreadable `lang_code` as empty rather than throwing -- a language tag
  /// must not cost the words beside it -- and empty means UNKNOWN there.
  /// Writing it out would put a language tag on the wire that names no
  /// language, which the reader then drops anyway.
  String? get langCode {
    for (final result in _ordered) {
      if (result.hasUsableTranscript) {
        final tag = result.langCode.split('-').first;
        return tag.isNotEmpty && tag.length <= maxLangCodeLength ? tag : null;
      }
    }
    return null;
  }
}
