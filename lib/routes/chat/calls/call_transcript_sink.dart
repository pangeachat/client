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

  final List<SpeechToTextResponseModel> _results = [];
  final Set<int> _transcribed = {};

  CallTranscriptSink({
    required this.transcribe,
    required this.userL1,
    required this.userL2,
  });

  /// Every transcript this call produced, in the order the audio was spoken.
  List<SpeechToTextResponseModel> get results => List.unmodifiable(_results);

  /// Whether anything was said that speech-to-text could read.
  bool get hasTranscript => _results.any((r) => r.results.isNotEmpty);

  @override
  Future<void> deliver(PcmChunk chunk) async {
    // A chunk is transcribed once. Redelivery — a retry, or a hangup racing a
    // flush — must not bill the route again or append the same words twice.
    if (!_transcribed.add(chunk.index)) return;

    try {
      _results.add(
        await transcribe(
          SpeechToTextRequestModel(
            audioContent: chunk.toWav(),
            config: SpeechToTextAudioConfigModel(
              encoding: AudioEncodingEnum.linear16,
              sampleRateHertz: chunk.sampleRate,
              userL1: userL1,
              userL2: userL2,
            ),
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
  /// does. The chunks are already frozen, so nothing is recomputed here — this
  /// is the union, and it is the same union however many times it is asked for.
  List<OneConstructUse> constructs({
    required String roomId,
    required String eventId,
  }) => [
    for (final result in _results)
      ...result.constructs(roomId, eventId, ConstructUseTypeEnum.pvc),
  ];

  /// The language the call was transcribed in, or null if nothing was.
  String? get langCode =>
      _results
          .firstWhere(
            (r) => r.results.isNotEmpty,
            orElse: () => SpeechToTextResponseModel(results: const []),
          )
          .results
          .isEmpty
      ? null
      : _results
            .firstWhere((r) => r.results.isNotEmpty)
            .langCode
            .split('-')
            .first;
}
