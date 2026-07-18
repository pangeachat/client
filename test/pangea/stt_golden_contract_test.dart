import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mime/mime.dart';

import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// Golden contract tests for the streaming-STT `user_stt` contract (#264).
///
/// The client parses the choreographer's `SpeechToTextResponse` and
/// re-serializes it into the Matrix `m.audio` event. These tests run that
/// round trip against the byte-shared golden fixture pack (identical copies
/// live in 2-step-choreographer and pangea-bot).
///
/// R0-2 fixed the three frozen defects, so the client now emits the corrected
/// shape (true-millisecond word times, `service` preserved) and parses an
/// empty exhausted-fallback response without throwing. The R0-1
/// characterization tripwires that pinned the OLD buggy shape have been
/// retired; the active groups assert the corrected target envelope
/// (`matrix_event_content_target.json`) plus a legacy-read guard that the
/// fixed parser still tolerates old inflated `..._current.json` events.
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
  // The client constructs MatrixAudioFile(bytes, name) with NO explicit
  // mimeType (chat.dart ~L1673), so the Matrix SDK resolves it from the
  // filename via the `mime` package (`lookupMimeType`). For `.wav` that is
  // `audio/x-wav`, NOT `audio/wav`. Derive it here from the same source the
  // SDK uses so this fixture can never silently diverge from real emission.
  final mimetype = lookupMimeType(fileName)!;
  final fileInfo = <String, dynamic>{'mimetype': mimetype, 'size': 20480};
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

  // R0-1 froze a "current behaviour (defects pinned green)" group whose tests
  // asserted the client PRODUCED the buggy shape (x1000-inflated word times,
  // dropped `service`, throw-on-empty). Those were characterization tripwires
  // for the R0-1 -> R0-2 transition. R0-2 (this change) fixed the defects, so
  // those assertions are now factually false and have been retired. They are
  // REPLACED below by permanent guards that assert the CORRECTED full-event
  // production (against matrix_event_content_target) plus backward-compatible
  // reading of legacy events that already persist in rooms. The precise
  // corrected embed values (true ms, service, empty-ok) are guarded by the
  // "target contract" group below. This is the standard characterization-test
  // lifecycle, not a weakening: coverage of correct behaviour is strictly
  // stronger than before.
  group('client emits the corrected full event + still reads legacy events', () {
    test('full m.audio event content matches matrix_event_content_target', () {
      // Assemble the whole event content the way the fixed client does,
      // embedding the REAL round-tripped user_stt (now true-ms + service), and
      // pin it against the entire TARGET fixture so no event-level field,
      // nested map, key, or formatting can drift unnoticed.
      final choreo = _loadJson('choreo_response_normal.json');
      final sttEmbed = SpeechToTextResponseModel.fromJson(
        Map<String, dynamic>.from(choreo),
      ).toJson();

      final content = _buildClientAudioEventContent(sttEmbed);
      final fixture = _loadJson('matrix_event_content_target.json');

      // Whole-content deep equality: every top-level key (incl. body/filename/
      // url/msgtype/speaker_l1/speaker_l2), the nested info + msc1767 audio
      // maps, and the corrected user_stt embed must match the fixture exactly.
      expect(content, equals(fixture));
      // Guard the exact key set too, so an added/removed field can never slip
      // past the map comparison.
      expect(
        content.keys.toSet(),
        equals(fixture.keys.toSet()),
        reason: 'client event content and fixture must have identical keys',
      );
      expect(content['filename'], 'recording.wav');
      expect(fixture['filename'], fixture['body']);
    });

    test('legacy inflated user_stt embed still parses without throwing', () {
      // Voice messages sent BEFORE the R0-2 fix persist in rooms with
      // x1000-inflated word times and no `service` field (the
      // matrix_event_content_current shape). The fixed parser must still read
      // them without crashing so old timelines keep rendering; no consumer
      // reads STT token timings today, but fromJson must not throw.
      final legacyEmbed =
          _loadJson('matrix_event_content_current.json')['user_stt']
              as Map<String, dynamic>;
      final model = SpeechToTextResponseModel.fromJson(
        Map<String, dynamic>.from(legacyEmbed),
      );
      expect(model.results, isNotEmpty);
      expect(model.transcript.sttTokens, isNotEmpty);
      // Legacy events carry no provenance; the nullable field reads null,
      // not a parse failure.
      expect(model.service, isNull);
    });
  });

  group('target contract (R0-2 implements these)', () {
    test('word times pass through as true milliseconds', () {
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
    });

    test('service provenance is preserved end to end', () {
      final choreo = _loadJson('choreo_response_normal.json');
      final roundTripped = SpeechToTextResponseModel.fromJson(
        Map<String, dynamic>.from(choreo),
      ).toJson();
      expect(roundTripped['service'], 'google');
    });

    test('empty exhausted-fallback response is handled without throwing', () {
      final empty = _loadJson('choreo_response_empty.json');
      final model = SpeechToTextResponseModel.fromJson(
        Map<String, dynamic>.from(empty),
      );
      expect(model.results, isEmpty);
    });
  });
}
