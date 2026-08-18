import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_request_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

PcmChunk chunk(int index, {int sampleRate = 16000}) => PcmChunk(
  pcm: Uint8List(sampleRate * 2),
  sampleRate: sampleRate,
  channels: 1,
  index: index,
);

/// An empty-but-valid response — the shape the route returns when nothing was
/// transcribable, which is a normal answer rather than a failure.
SpeechToTextResponseModel get silent =>
    SpeechToTextResponseModel(results: const []);

void main() {
  late List<SpeechToTextRequestModel> sent;

  CallTranscriptSink sink({
    SpeechToTextResponseModel Function(int call)? respond,
    Set<int> failOn = const {},
  }) {
    sent = [];
    return CallTranscriptSink(
      userL1: 'en',
      userL2: 'es',
      transcribe: (request) async {
        final index = sent.length;
        sent.add(request);
        if (failOn.contains(index)) throw StateError('provider refused');
        return respond?.call(index) ?? silent;
      },
    );
  }

  group('CallTranscriptSink', () {
    test('sends each chunk as WAV at the rate it was captured', () async {
      final s = sink();
      await s.deliver(chunk(0));

      expect(sent, hasLength(1));
      expect(sent.single.config.sampleRateHertz, 16000);
      expect(sent.single.config.userL1, 'en');
      expect(sent.single.config.userL2, 'es');
      expect(
        String.fromCharCodes(sent.single.audioContent.sublist(0, 4)),
        'RIFF',
        reason: 'the route takes a container, not bare samples',
      );
    });

    test('a chunk is transcribed once however often it is delivered', () async {
      // The route is billed per call, and appending the same words twice would
      // credit the learner twice for saying something once.
      final s = sink();
      await s.deliver(chunk(0));
      await s.deliver(chunk(0));
      await s.deliver(chunk(1));
      await s.deliver(chunk(0));

      expect(sent, hasLength(2));
      expect(s.results, hasLength(2));
    });

    test('a chunk that fails costs its own words and no more', () async {
      final s = sink(failOn: {0});
      await s.deliver(chunk(0));
      await s.deliver(chunk(1));

      expect(sent, hasLength(2), reason: 'the call carried on');
      expect(s.results, hasLength(1));
    });

    test('a failed chunk is not retried into a double charge', () async {
      final s = sink(failOn: {0});
      await s.deliver(chunk(0));
      await s.deliver(chunk(0));
      expect(
        sent,
        hasLength(1),
        reason: 'the index stays claimed, so a redelivery cannot bill again',
      );
    });

    test('reports whether anything was actually said', () async {
      final s = sink();
      expect(s.hasTranscript, isFalse);
      await s.deliver(chunk(0));
      expect(
        s.hasTranscript,
        isFalse,
        reason: 'a silent chunk is a real answer, not a transcript',
      );
    });

    test('a call that transcribed nothing produces no constructs', () async {
      final s = sink();
      await s.deliver(chunk(0));
      expect(s.constructs(roomId: '!r:server', eventId: '\$e'), isEmpty);
      expect(s.langCode, isNull);
    });

    test('the batch is the same however often it is asked for', () async {
      // It is the union of frozen results, so asking twice is not a recount.
      final s = sink();
      await s.deliver(chunk(0));
      final first = s.constructs(roomId: '!r:server', eventId: '\$e');
      final second = s.constructs(roomId: '!r:server', eventId: '\$e');
      expect(first.length, second.length);
    });

    test('call speech is credited as pvc, which counts as speaking', () {
      // The type the client emits has to be one the server scores; an unknown
      // one silently scores zero rather than failing.
      expect(
        ConstructUseTypeEnum.pvc.pointValue,
        ConstructUseTypeEnum.pvm.pointValue,
      );
      expect(
        ConstructUseTypeEnum.pvc.skillsEnumType,
        ConstructUseTypeEnum.pvm.skillsEnumType,
      );
    });
  });
}
