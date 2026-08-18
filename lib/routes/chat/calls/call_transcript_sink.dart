import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
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

  /// The finished batch, kept once built. See [constructs].
  ({String roomId, String eventId, List<OneConstructUse> uses})? _batch;

  CallTranscriptSink({
    required this.transcribe,
    required this.userL1,
    required this.userL2,
  });

  /// Every transcript this call produced, in the order the audio was spoken.
  List<SpeechToTextResponseModel> get results => [
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
  Future<void> deliver(PcmChunk chunk) async {
    // A chunk is transcribed once. Redelivery — a retry, or a hangup racing a
    // flush — must not bill the route again or count the same words twice.
    if (!_transcribed.add(chunk.index)) return;

    try {
      _byIndex[chunk.index] = await transcribe(
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
    } catch (e, s) {
      // This chunk's words are lost and the rest of the call still counts.
      // Releasing the index would let a retry double-count, so it stays claimed.
      Logs().w('Could not transcribe call chunk ${chunk.index}', e, s);
    }
  }

  @override
  Future<void> close() async {}

  /// The call's speaking analytics, as one batch.
  ///
  /// Built at the end rather than per chunk because the constructs are anchored
  /// to the call's timeline event, and that event does not exist until the call
  /// does.
  ///
  /// **Built once and kept.** Each use is stamped with the moment it was made,
  /// so recomputing yields a batch that differs from the one already recorded.
  /// The union has to be one fixed set of uses, not a recipe that produces a new
  /// set every time it is read.
  List<OneConstructUse> constructs({
    required String roomId,
    required String eventId,
  }) {
    final existing = _batch;
    if (existing != null &&
        existing.roomId == roomId &&
        existing.eventId == eventId) {
      return existing.uses;
    }
    final uses = List<OneConstructUse>.unmodifiable([
      for (final result in results)
        if (result.hasUsableTokens)
          ...result.constructs(roomId, eventId, ConstructUseTypeEnum.pvc),
    ]);
    _batch = (roomId: roomId, eventId: eventId, uses: uses);
    return uses;
  }

  /// The language the call was transcribed in, or null if nothing was.
  ///
  /// Taken from the first chunk that produced anything: the speaker's target
  /// language is pinned for the whole call, so every chunk agrees and the
  /// earliest answer is the call's answer.
  String? get langCode {
    for (final result in results) {
      if (result.hasUsableTranscript) {
        return result.langCode.split('-').first;
      }
    }
    return null;
  }
}
