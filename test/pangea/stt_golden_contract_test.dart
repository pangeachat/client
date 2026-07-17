import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// Golden contract tests for the streaming-STT `user_stt` freeze (R0-1).
///
/// The client parses the choreographer's `SpeechToTextResponse` and
/// re-serializes it into the Matrix `m.audio` event. These tests run that
/// round trip against the byte-shared golden fixture pack (identical copies
/// live in 2-step-choreographer and pangea-bot) and pin today's real
/// behaviour: word times inflated x1000, the `service` field dropped, and an
/// empty response throwing.
///
/// Current-behaviour tests are GREEN and document those defects. Target tests
/// are `skip`-labelled `R0-2`: the R0-2 defect-fix wave removes the skip and
/// makes the round trip match `matrix_event_content_target.json`.
const String _goldenDir = 'test/pangea/stt_golden';

Map<String, dynamic> _loadJson(String name) {
  final raw = File('$_goldenDir/$name').readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// Reconstructs the FULL `m.audio` event content the client emits for a voice
/// message, so the golden fixture is pinned as real client output rather than
/// just its `user_stt` embed. Any drift in a top-level field, the nested
/// `info` / `org.matrix.msc1767.audio` maps, or the `user_stt` serialization
/// then fails the deep-equality assertion.
///
/// Mirrors two real code paths for the fixture's fixed inputs:
///  - the Matrix SDK `Room.sendFileEvent` base content for an unencrypted
///    room (`matrix` room.dart ~L1001): `msgtype`, `body`, `filename`
///    (== `body` == `file.name`), `url`, `info`;
///  - `chat.dart` `voiceMessageAction` `extraContent` (~L1700-1711): the `info`
///    override with `duration`, the msc3245 voice marker, the msc1767 audio
///    block, `speaker_l1` / `speaker_l2`, and `user_stt`.
///
/// `userSttEmbed` MUST come from the real `SpeechToTextResponseModel` round
/// trip so this pins the client's actual serialization, not a copy of it.
Map<String, dynamic> _buildClientAudioEventContent(
  Map<String, dynamic> userSttEmbed,
) {
  const fileName = 'recording.wav';
  const url = 'mxc://staging.pangea.chat/EXAMPLESTTGOLDENfixture0001';
  const duration = 2000;
  const waveform = <int>[0, 256, 512, 256, 0];
  final fileInfo = <String, dynamic>{'mimetype': 'audio/wav', 'size': 20480};
  return <String, dynamic>{
    // matrix SDK Room.sendFileEvent base content (unencrypted room)
    'msgtype': 'm.audio',
    'body': fileName,
    'filename': fileName,
    'url': url,
    // chat.dart overrides info via extraContent: {...file.info, duration}
    'info': <String, dynamic>{...fileInfo, 'duration': duration},
    // chat.dart voiceMessageAction extraContent
    'org.matrix.msc3245.voice': <String, dynamic>{},
    'org.matrix.msc1767.audio': <String, dynamic>{
      'duration': duration,
      'waveform': waveform,
    },
    'speaker_l1': 'en',
    'speaker_l2': 'es',
    'user_stt': userSttEmbed,
  };
}

void main() {
  group('golden fixture pack integrity', () {
    test('data fixtures match MANIFEST.sha256', () {
      final manifest = File('$_goldenDir/MANIFEST.sha256').readAsLinesSync();
      final expected = <String, String>{};
      for (final line in manifest) {
        if (line.trim().isEmpty) continue;
        final parts = line.trim().split(RegExp(r'\s+'));
        expected[parts[1]] = parts[0];
      }
      expect(
        expected.length,
        5,
        reason: 'manifest must pin exactly the 5 data fixtures',
      );
      expected.forEach((name, digest) {
        final bytes = File('$_goldenDir/$name').readAsBytesSync();
        expect(
          sha256.convert(bytes).toString(),
          digest,
          reason: '$name drifted from the canonical golden pack',
        );
      });
    });
  });

  group('current behaviour (defects pinned green)', () {
    test('fromJson -> toJson matches the current inflated user_stt embed', () {
      final choreo = _loadJson('choreo_response_normal.json');
      final roundTripped = SpeechToTextResponseModel.fromJson(
        Map<String, dynamic>.from(choreo),
      ).toJson();

      final expectedEmbed =
          _loadJson('matrix_event_content_current.json')['user_stt']
              as Map<String, dynamic>;
      expect(roundTripped, equals(expectedEmbed));
    });

    test('full m.audio event content matches matrix_event_content_current', () {
      // Assemble the whole event content the way the client does, embedding the
      // REAL round-tripped user_stt, and pin it against the entire fixture so no
      // event-level field, nested map, key, or formatting can drift unnoticed
      // while only the user_stt embed is checked.
      final choreo = _loadJson('choreo_response_normal.json');
      final sttEmbed = SpeechToTextResponseModel.fromJson(
        Map<String, dynamic>.from(choreo),
      ).toJson();

      final content = _buildClientAudioEventContent(sttEmbed);
      final fixture = _loadJson('matrix_event_content_current.json');

      // Whole-content deep equality: every top-level key (incl. body/filename/
      // url/msgtype/speaker_l1/speaker_l2), the nested info + msc1767 audio
      // maps, and the user_stt embed must match the fixture exactly.
      expect(content, equals(fixture));
      // Guard the exact key set too, so an added/removed field can never slip
      // past the map comparison.
      expect(
        content.keys.toSet(),
        equals(fixture.keys.toSet()),
        reason: 'client event content and fixture must have identical keys',
      );
      // filename is what the R0-1 codex-fix added: the Matrix SDK sendFileEvent
      // sets filename == body == file.name; assert both explicitly.
      expect(content['filename'], 'recording.wav');
      expect(fixture['filename'], 'recording.wav');
      expect(fixture['filename'], fixture['body']);
    });

    test('word times are inflated x1000 on the round trip', () {
      final choreo = _loadJson('choreo_response_normal.json');
      final model = SpeechToTextResponseModel.fromJson(
        Map<String, dynamic>.from(choreo),
      );
      // Server emits ms; the client STTToken parse multiplies by 1000.
      final mundo = model.transcript.sttTokens[1];
      expect(mundo.startTime!.inMilliseconds, 480000);
      expect(mundo.endTime!.inMilliseconds, 960000);
    });

    test('service provenance is dropped by the client model', () {
      final choreo = _loadJson('choreo_response_normal.json');
      expect(choreo.containsKey('service'), isTrue);
      final roundTripped = SpeechToTextResponseModel.fromJson(
        Map<String, dynamic>.from(choreo),
      ).toJson();
      expect(roundTripped.containsKey('service'), isFalse);
    });

    test('empty exhausted-fallback response throws on parse', () {
      final empty = _loadJson('choreo_response_empty.json');
      expect(
        () => SpeechToTextResponseModel.fromJson(
          Map<String, dynamic>.from(empty),
        ),
        throwsException,
      );
    });
  });

  group('target contract (R0-2 implements these)', () {
    test(
      'word times pass through as true milliseconds',
      () {
        final choreo = _loadJson('choreo_response_normal.json');
        final model = SpeechToTextResponseModel.fromJson(
          Map<String, dynamic>.from(choreo),
        );
        final mundo = model.transcript.sttTokens[1];
        expect(mundo.startTime!.inMilliseconds, 480);
        expect(mundo.endTime!.inMilliseconds, 960);

        final expectedEmbed =
            _loadJson('matrix_event_content_target.json')['user_stt']
                as Map<String, dynamic>;
        expect(model.toJson()['results'], equals(expectedEmbed['results']));
      },
      skip:
          'R0-2: stop multiplying server milliseconds by 1000 on parse/serialize',
    );

    test(
      'service provenance is preserved end to end',
      () {
        final choreo = _loadJson('choreo_response_normal.json');
        final roundTripped = SpeechToTextResponseModel.fromJson(
          Map<String, dynamic>.from(choreo),
        ).toJson();
        expect(roundTripped['service'], 'google');
      },
      skip: 'R0-2: read and re-emit the top-level service field',
    );

    test(
      'empty exhausted-fallback response is handled without throwing',
      () {
        final empty = _loadJson('choreo_response_empty.json');
        final model = SpeechToTextResponseModel.fromJson(
          Map<String, dynamic>.from(empty),
        );
        expect(model.results, isEmpty);
      },
      skip: 'R0-2: parse an empty response gracefully instead of throwing',
    );
  });
}
