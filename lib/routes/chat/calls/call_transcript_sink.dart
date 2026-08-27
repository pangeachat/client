import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
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
  final Set<int> _transcribed = {};

  /// Each chunk's uses, built once and kept. See [constructs].
  final Map<int, List<OneConstructUse>> _usesByIndex = {};

  /// What [_usesByIndex] was built against. Different anchors are a different
  /// batch, so the old one is discarded rather than mixed with the new.
  ({String roomId, String eventId})? _anchor;

  CallTranscriptSink({
    required this.transcribe,
    required this.userL1,
    required this.userL2,
  });

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

    // A chunk is transcribed once. Redelivery — a retry, or a hangup racing a
    // flush — must not bill the route again or count the same words twice.
    if (!_transcribed.add(chunk.index)) return Future.value();

    // A block, not an arrow. Removing from the map RETURNS the future being
    // removed, and whenComplete waits for a future its callback returns — so
    // the arrow form makes this future wait for itself and it never completes.
    final work = _transcribeChunk(chunk, within).whenComplete(() {
      _running.remove(chunk.index);
    });
    _running[chunk.index] = work;
    return work;
  }

  /// Transcriptions still running, by chunk. Closing waits for these: the words
  /// are read the moment the call is over, and one still in flight would be
  /// missing from them.
  final Map<int, Future<void>> _running = {};

  Future<void> _transcribeChunk(PcmChunk chunk, Duration? within) async {
    try {
      // Bounded here, where the request is, so that giving up on it is a
      // failure of the attempt: the index is released below and the next
      // attempt issues a genuinely new request. Bounded by the waiter instead,
      // the abandoned one stayed listed as in flight and every retry waited on
      // it again — three attempts that were only ever one.
      final request = transcribe(
        SpeechToTextRequestModel(
          audioContent: chunk.toWav(),
          config: SpeechToTextAudioConfigModel(
            encoding: AudioEncodingEnum.linear16,
            sampleRateHertz: chunk.sampleRate,
            userL1: userL1,
            userL2: userL2,
          ),
        ),
      );
      _byIndex[chunk.index] = await (within == null
          ? request
          : request.timeout(within));
    } catch (e, s) {
      // Released and re-thrown, so the caller's retry can try again. Swallowing
      // this reported success to a caller whose whole purpose is to retry, and
      // one bad moment from the provider cost that chunk's words for good.
      //
      // The index is only kept once there is something to keep: a chunk that
      // was transcribed must never be transcribed twice, but one that was not
      // has nothing to double-count.
      _transcribed.remove(chunk.index);
      Logs().w('Could not transcribe call chunk ${chunk.index}', e, s);
      rethrow;
    }
  }

  /// How long closing waits for transcriptions still running.
  ///
  /// They carry their own limits, so this only exists so that a stuck one cannot
  /// hold the end of a call open for ever.
  static const _settleWithin = Duration(seconds: 60);

  @override
  Future<void> close() async {
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
    final deadline = DateTime.now().add(_settleWithin);
    while (_running.isNotEmpty) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        Logs().w(
          'Gave up waiting for a call transcription; its words are lost',
        );
        return;
      }
      try {
        await Future.wait(
          List.of(_running.values).map((work) => work.catchError((_) {})),
        ).timeout(left);
      } on TimeoutException {
        Logs().w(
          'Gave up waiting for a call transcription; its words are lost',
        );
        return;
      }
    }
  }

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

  /// The language the call was transcribed in, or null if nothing was.
  ///
  /// Taken from the first chunk that produced anything: the speaker's target
  /// language is pinned for the whole call, so every chunk agrees and the
  /// earliest answer is the call's answer.
  String? get langCode {
    for (final result in _ordered) {
      if (result.hasUsableTranscript) {
        return result.langCode.split('-').first;
      }
    }
    return null;
  }
}
