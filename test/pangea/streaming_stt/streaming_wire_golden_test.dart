import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_session.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_audio_capture.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_repo.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_state.dart';

/// Byte-shared frozen neutral-wire golden pack (identical copy in
/// 2-step-choreographer). Proves the migrated client parses each frozen frame
/// into the SAME client-visible signals the old Deepgram-shaped wire produced.
const String _goldenDir = 'test/pangea/streaming_stt/streaming_wire_golden';

String _readGolden(String name) => File('$_goldenDir/$name').readAsStringSync();

Map<String, dynamic> _loadGolden(String name) =>
    jsonDecode(_readGolden(name)) as Map<String, dynamic>;

/// A capture stub — the golden test only exercises parse/accumulate, never the
/// mic or socket, so every method is an inert no-op.
class _NoopCapture implements SttAudioCaptureApi {
  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> start(
    void Function(Uint8List frame) onFrame, {
    void Function(Object error)? onError,
  }) async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

SttStreamRepo _repo() => SttStreamRepo(
  wsUrl: 'wss://example/choreo/speech_to_text/stream',
  accessToken: 'T',
  lang: 'en',
  connector: (Uri uri, {Iterable<String>? protocols}) =>
      throw UnimplementedError('the golden test never opens a socket'),
);

void main() {
  group('golden pack integrity', () {
    test('the five wire_*.json match MANIFEST.sha256', () {
      final lines = File('$_goldenDir/MANIFEST.sha256').readAsLinesSync();
      final expected = <String, String>{};
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final parts = line.trim().split(RegExp(r'\s+'));
        expected[parts[1]] = parts[0];
      }
      expect(
        expected.keys.toSet(),
        <String>{
          'wire_partial.json',
          'wire_segment_final.json',
          'wire_stream_final.json',
          'wire_speech_boundary.json',
          'wire_error.json',
        },
        reason:
            'manifest must pin exactly the five data files (not itself/README)',
      );
      expected.forEach((name, digest) {
        final bytes = File('$_goldenDir/$name').readAsBytesSync();
        expect(
          sha256.convert(bytes).toString(),
          digest,
          reason: '$name drifted',
        );
      });
    });
  });

  group('parser behaviour-identical (SttPartial.fromJson)', () {
    // The (isFinal, speechFinal) equivalence table the OLD is_final/speech_final
    // booleans produced, now derived from the neutral type.
    test('wire_partial -> isFinal=false, speechFinal=false', () {
      final p = SttPartial.fromJson(_loadGolden('wire_partial.json'));
      expect(p.isFinal, isFalse);
      expect(p.speechFinal, isFalse);
      expect(p.transcript, _loadGolden('wire_partial.json')['transcript']);
      expect(p.words, isNotEmpty);
    });

    test('wire_segment_final -> isFinal=true, speechFinal=false', () {
      final p = SttPartial.fromJson(_loadGolden('wire_segment_final.json'));
      expect(p.isFinal, isTrue);
      expect(p.speechFinal, isFalse);
    });

    test('wire_stream_final -> isFinal=true, speechFinal=true', () {
      final p = SttPartial.fromJson(_loadGolden('wire_stream_final.json'));
      expect(p.isFinal, isTrue);
      expect(p.speechFinal, isTrue);
    });

    test(
      'wire_speech_boundary -> one utteranceEnds event, zero partials',
      () async {
        final repo = _repo();
        final partials = <SttPartial>[];
        var boundaries = 0;
        repo.partials.listen(partials.add);
        repo.utteranceEnds.listen((_) => boundaries++);

        repo.debugHandleInbound(_readGolden('wire_speech_boundary.json'));
        await pumpEventQueue();

        expect(boundaries, 1);
        expect(partials, isEmpty);
      },
    );

    test('wire_error -> teardown to SttStreamState.error', () async {
      final repo = _repo();
      final states = <SttStreamState>[];
      repo.state.listen(states.add);

      repo.debugHandleInbound(_readGolden('wire_error.json'));
      await pumpEventQueue();

      expect(states, contains(SttStreamState.error));
    });
  });

  group('session-layer behaviour-identical (StreamingSttSession)', () {
    test(
      'partial -> segment_final -> stream_final accumulate exactly as the old '
      'is_final/speech_final booleans did (multi-segment append)',
      () {
        final session = StreamingSttSession(
          capture: _NoopCapture(),
          repo: _repo(),
        );

        // A partial is interim only: it shows in the live transcript, commits
        // nothing.
        final partialText =
            _loadGolden('wire_partial.json')['transcript'] as String;
        session.debugApplyPartial(
          SttPartial.fromJson(_loadGolden('wire_partial.json')),
        );
        expect(session.liveTranscript, partialText);
        expect(session.finalTranscript, '');

        // segment_final (isFinal true) commits its segment.
        final segText =
            _loadGolden('wire_segment_final.json')['transcript'] as String;
        session.debugApplyPartial(
          SttPartial.fromJson(_loadGolden('wire_segment_final.json')),
        );
        expect(session.finalTranscript, segText);

        // stream_final (isFinal true) APPENDS a second committed segment —
        // never overwrites — so both survive in the final transcript + words.
        final streamText =
            _loadGolden('wire_stream_final.json')['transcript'] as String;
        session.debugApplyPartial(
          SttPartial.fromJson(_loadGolden('wire_stream_final.json')),
        );
        expect(session.finalTranscript, '$segText $streamText');
        expect(session.liveTranscript, '$segText $streamText');

        final segWords =
            (_loadGolden('wire_segment_final.json')['words'] as List).length;
        final streamWords =
            (_loadGolden('wire_stream_final.json')['words'] as List).length;
        expect(session.finalWords.length, segWords + streamWords);
      },
    );
  });
}
