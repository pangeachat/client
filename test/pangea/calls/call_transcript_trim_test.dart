import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/calls/call_upload_gate.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/calls/speech_trim.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_request_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// The real call chunk: ~22s of this device's own noise floor while the other
/// person talked, then ~18s of speech. See `speech_trim_test.dart`.
const _fixture = 'test/pangea/calls/fixtures/call_noise_then_speech.wav';

late final Int16List _audio;

Int16List _load() {
  final bytes = File(_fixture).readAsBytesSync();
  final pcm = bytes.sublist(44);
  return Int16List.view(Uint8List.fromList(pcm).buffer, 0, pcm.length ~/ 2);
}

Int16List _range(double fromSec, double toSec) => Int16List.sublistView(
  _audio,
  (fromSec * 16000).round(),
  (toSec * 16000).round(),
);

const _chunkStart = 1700000000000;

PcmChunk _chunk(Int16List samples, {int index = 0}) => PcmChunk(
  pcm: Uint8List.view(
    samples.buffer,
    samples.offsetInBytes,
    samples.lengthInBytes,
  ),
  sampleRate: 16000,
  channels: 1,
  index: index,
  startedAtMs: _chunkStart,
);

SpeechToTextResponseModel _response(
  String text, {
  List<(String, int?, int?)>? timings,
}) => SpeechToTextResponseModel.fromJson({
  'results': [
    {
      'transcripts': [
        {
          'transcript': text,
          'confidence': 90,
          'stt_tokens': <dynamic>[],
          'lang_code': 'en-US',
          'words_per_hr': null,
          if (timings != null)
            'word_timings': [
              for (final (word, start, end) in timings)
                {
                  'word': word,
                  'start_time_ms': start,
                  'end_time_ms': end,
                  'confidence': 90,
                },
            ],
        },
      ],
    },
  ],
});

void main() {
  setUpAll(() {
    _audio = _load();
  });

  // These sinks take the process-wide upload gate. See call_record_test.
  setUp(CallUploadGate.resetShared);

  group('a chunk with nothing said in it', () {
    test('is never sent, and never billed', () async {
      var calls = 0;
      final sink = CallTranscriptSink(
        transcribe: (_) async {
          calls++;
          return _response('Hey.');
        },
        userL1: 'en',
        userL2: 'hi',
      );

      await sink.deliver(_chunk(_range(0, 22)));

      // Whisper reads this stretch as a fabricated "Hey." and Deepgram returns
      // zero words or a repeated hallucination for its spans. Sending it can
      // only invent words and put them in a learner's mouth.
      expect(calls, 0, reason: 'nothing was said, so nothing was asked');
      expect(sink.hasTranscript, isFalse);
    });

    test('is counted as captured, and NOT as lost', () async {
      final sink = CallTranscriptSink(
        transcribe: (_) async => _response('x'),
        userL1: 'en',
        userL2: 'hi',
      );

      await sink.deliver(_chunk(_range(0, 22)));

      // Captured is the denominator: audio that existed. A chunk we chose not
      // to send used to vanish from it entirely, which is the opposite of what
      // that accounting is for.
      expect(sink.chunksCaptured, 1);
      expect(sink.chunksSuppressed, 1);
      // Nothing was DROPPED. The audio was examined and held nothing, so
      // marking it lost would flag a gap in almost every real call and leave
      // the flag meaning nothing when it matters.
      expect(sink.chunksLost, 0);
      expect(sink.chunksTranscribed, 0);
    });

    test('is not examined again when it is redelivered', () async {
      var calls = 0;
      final sink = CallTranscriptSink(
        transcribe: (_) async {
          calls++;
          return _response('x');
        },
        userL1: 'en',
        userL2: 'hi',
      );

      final chunk = _chunk(_range(0, 22));
      await sink.deliver(chunk);
      await sink.deliver(chunk);
      await sink.deliver(chunk);

      expect(calls, 0);
      // A retry or a hangup racing a flush must not make one chunk of audio
      // count as three.
      expect(sink.chunksCaptured, 1);
      expect(sink.chunksSuppressed, 1);
    });
  });

  group('a chunk whose audio could not even be read', () {
    test('is recorded as LOST, not as silence', () async {
      var calls = 0;
      final sink = CallTranscriptSink(
        transcribe: (_) async {
          calls++;
          return _response('x');
        },
        userL1: 'en',
        userL2: 'hi',
      );

      // A malformed chunk: reading it divides by its channel count. The point
      // is not this particular defect but that ANY throw out of the trim is
      // accounted for, because the trim walks the chunk's bytes and byte
      // walking can fail.
      final broken = PcmChunk(
        pcm: Uint8List(16000 * 2 * 10),
        sampleRate: 16000,
        channels: 0,
        index: 7,
        startedAtMs: _chunkStart,
      );

      await expectLater(sink.deliver(broken), throwsA(anything));

      expect(calls, 0);
      // NOT silence. Read outside the failure accounting, a throw here left the
      // index claimed with nothing to release it: the chunk published as
      // captured, not transcribed and not lost -- character for character how a
      // chunk the PROVIDER read as silence looks. Speech this device dropped
      // would have been indistinguishable from speech nobody spoke.
      expect(sink.chunksLost, 1);
      expect(sink.chunksSuppressed, 0);
      expect(sink.chunksCaptured, 1);
    });

    test('can be retried, because the failure released its index', () async {
      var calls = 0;
      final sink = CallTranscriptSink(
        transcribe: (_) async {
          calls++;
          return _response('hello');
        },
        userL1: 'en',
        userL2: 'hi',
      );

      await expectLater(
        sink.deliver(
          PcmChunk(
            pcm: Uint8List(16000 * 2 * 10),
            sampleRate: 16000,
            channels: 0,
            index: 3,
            startedAtMs: _chunkStart,
          ),
        ),
        throwsA(anything),
      );

      // The same index, delivered again with audio that can be read. A retry
      // that found the index still taken would have returned as though it had
      // succeeded, and the words would be lost with nothing saying so.
      await sink.deliver(_chunk(_range(22.3, 40.2), index: 3));

      expect(calls, 1);
      expect(sink.chunksLost, 0, reason: 'the retry is no longer a loss');
      expect(sink.chunksTranscribed, 1);
      expect(sink.chunksCaptured, 1);
    });
  });

  group('a chunk that was trimmed', () {
    test('is sent as the trimmed audio, not the whole chunk', () async {
      Uint8List? sent;
      final sink = CallTranscriptSink(
        transcribe: (SpeechToTextRequestModel request) async {
          sent = request.audioContent;
          return _response('hello');
        },
        userL1: 'en',
        userL2: 'hi',
      );

      await sink.deliver(_chunk(_audio));

      expect(sent, isNotNull);
      // The whole chunk is 40.4s; what goes out is the ~18s somebody spoke.
      final wholeBytes = _audio.lengthInBytes + 44;
      expect(sent!.lengthInBytes, lessThan(0.6 * wholeBytes));
    });

    test('places its words at the moment they were spoken', () async {
      final sink = CallTranscriptSink(
        transcribe: (_) async => _response(
          'hello world',
          timings: [('hello', 0, 400), ('world', 500, 900)],
        ),
        userL1: 'en',
        userL2: 'hi',
      );

      await sink.deliver(_chunk(_audio));
      final segments = sink.segments;

      expect(segments, hasLength(1));
      // The provider timed "hello" at 0ms into the audio IT WAS GIVEN, and that
      // audio began about 22 seconds into the chunk. Left unshifted, the word
      // would be placed at the top of the chunk -- twenty-two seconds before
      // anybody spoke, and ahead of everything the other speaker said in
      // between.
      final at = segments.first.atMs!;
      expect(
        at - _chunkStart,
        inInclusiveRange(19000, 22800),
        reason: 'the offset must carry the trim with it',
      );
    });

    test('measures its words against the audio that was sent', () async {
      // A word timed past the end of the audio it claims to describe is not a
      // position. The ceiling has to be the TRIMMED length: against the whole
      // chunk's 40.4s this sequence looks perfectly well formed, and its
      // fabricated 30s timing would be believed.
      final sink = CallTranscriptSink(
        transcribe: (_) async => _response(
          'hello world',
          timings: [('hello', 0, 400), ('world', 30000, 30400)],
        ),
        userL1: 'en',
        userL2: 'hi',
      );

      await sink.deliver(_chunk(_audio));
      final segments = sink.segments;

      // Refused as a per-word sequence, so every segment falls back to the one
      // offset the chunk has evidence for rather than claiming 30s.
      for (final segment in segments) {
        expect(
          segment.atMs! - _chunkStart,
          lessThan(41000),
          reason: 'no word sits outside the chunk it came from',
        );
      }
    });
  });

  group('the settings are reachable', () {
    test(
      'a chunk held silent by default can be sent by loosening the trim',
      () async {
        var calls = 0;
        Future<SpeechToTextResponseModel> transcribe(_) async {
          calls++;
          return _response('x');
        }

        final strict = CallTranscriptSink(
          transcribe: transcribe,
          userL1: 'en',
          userL2: 'hi',
        );
        await strict.deliver(_chunk(_range(0, 22)));
        expect(calls, 0);

        // Every number in the detector is calibrated against ONE recording, so
        // each has to be reachable from outside -- a constant nothing can move is
        // a constant nothing can retune when the second sample arrives.
        final loose = CallTranscriptSink(
          transcribe: transcribe,
          userL1: 'en',
          userL2: 'hi',
          trimSettings: const SpeechTrimSettings(
            minTrimmable: Duration(days: 1),
          ),
        );
        await loose.deliver(_chunk(_range(0, 22)));
        expect(calls, 1);
      },
    );
  });
}
