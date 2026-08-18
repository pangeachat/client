// ignore_for_file: avoid_print
// ^ This is a command-line script, not app code: its printed output IS its
//   result. Nothing here ships in the app or runs under `flutter test`.
//
// Live end-to-end for the analytics half of a call, against the LOCAL stack.
//
// Deliberately outside `flutter test`: it needs a running choreographer and it
// spends money — the speech-to-text route calls a real provider. Run it by hand:
//
//   flutter test test/pangea/calls/e2e/call_analytics_e2e.dart
//
// The filename ends `_e2e`, not `_test`, so `flutter test` never picks it up on
// its own — it runs only when named explicitly.
//
// It drives the REAL PcmChunker and CallTranscriptSink over a real recording, so
// what it proves is the actual capture-to-analytics path, not a reimplementation
// of it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:http/http.dart' as http;

import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

const _choreo = 'http://localhost:8012';
const _synapse = 'http://localhost:8008';
const _fixture =
    '/Users/balla/PangeaChat/2-step-choreographer/app/handlers/'
    'speech_to_text/streaming/__tests__/deepgram_raw_fixtures/source/en_short.wav';

var _calls = 0;

Future<String> _login() async {
  final response = await http.post(
    Uri.parse('$_synapse/_matrix/client/v3/login'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'type': 'm.login.password',
      'identifier': {'type': 'm.id.user', 'user': 'learner'},
      'password': 'learnerpass',
    }),
  );
  return jsonDecode(response.body)['access_token'] as String;
}

/// Reads a 16-bit PCM WAV as samples, skipping the header.
Int16List _samplesOf(String path) {
  final bytes = File(path).readAsBytesSync();
  return Int16List.sublistView(Uint8List.fromList(bytes.sublist(44)));
}

void main() {
  test(
    'a real recording becomes real speaking analytics',
    () async {
      print('call analytics end-to-end (LIVE — this spends money)\n');

      final token = await _login();
      final samples = _samplesOf(_fixture);
      final seconds = samples.length / captureSampleRate;
      print(
        'fixture: ${seconds.toStringAsFixed(1)}s at ${captureSampleRate}Hz',
      );

      // A short ceiling so one recording produces several chunks, which is what
      // makes the union and the freezing observable rather than theoretical.
      final chunker = PcmChunker(
        sampleRate: captureSampleRate,
        channels: captureChannels,
        targetDuration: const Duration(seconds: 3),
        maxDuration: const Duration(seconds: 5),
        minSilence: const Duration(milliseconds: 300),
      );

      final sink = CallTranscriptSink(
        userL1: 'es',
        userL2: 'en',
        transcribe: (request) async {
          _calls++;
          final response = await http.post(
            Uri.parse('$_choreo/choreo/speech_to_text'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
            },
            body: jsonEncode(request.toJson()),
          );
          if (response.statusCode != 200) {
            throw StateError('stt ${response.statusCode}: ${response.body}');
          }
          return SpeechToTextResponseModel.fromJson(
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
          );
        },
      );

      // Deliver in device-sized frames, the way the capture tap actually does.
      final frame = captureSampleRate ~/ 50; // 20ms
      final chunks = <PcmChunk>[];
      for (var i = 0; i < samples.length; i += frame) {
        final end = i + frame < samples.length ? i + frame : samples.length;
        chunks.addAll(chunker.add(Int16List.sublistView(samples, i, end)));
      }
      final tail = chunker.flush();
      if (tail != null) chunks.add(tail);

      print(
        'chunker produced ${chunks.length} chunks: '
        '${chunks.map((c) => '${c.duration.inMilliseconds}ms').join(', ')}',
      );

      final delivered = chunks.fold<int>(
        0,
        (n, c) => n + c.pcm.lengthInBytes ~/ 2,
      );
      _check(
        'every sample survived chunking',
        delivered == samples.length,
        '$delivered of ${samples.length}',
      );

      for (final chunk in chunks) {
        await sink.deliver(chunk);
        print('  chunk ${chunk.index}: transcribed');
      }

      // Redeliver everything: exactly-once must hold against a real provider too.
      final callsBefore = _calls;
      for (final chunk in chunks) {
        await sink.deliver(chunk);
      }
      _check(
        'redelivery bills nothing',
        _calls == callsBefore,
        'billed ${_calls - callsBefore} extra',
      );

      print('\ntranscripts:');
      for (final text in sink.transcripts) {
        print('  "$text"');
      }
      if (sink.transcripts.length < sink.chunkCount) {
        print(
          '  (${sink.chunkCount - sink.transcripts.length} '
          'chunk(s) transcribed to nothing)',
        );
      }

      _check(
        'something was transcribed',
        sink.hasTranscript,
        'nothing came back',
      );

      final uses = sink.constructs(
        roomId: '!e2e:pangea.localhost',
        eventId: '\$e2e',
      );
      _check('the call produced construct uses', uses.isNotEmpty, '0 uses');
      _check(
        'every use is pvc',
        uses.every((u) => u.useType == ConstructUseTypeEnum.pvc),
        uses.map((u) => u.useType.name).toSet().join(','),
      );
      _check(
        'pvc counts as speaking',
        ConstructUseTypeEnum.pvc.skillsEnumType.name == 'speaking',
        ConstructUseTypeEnum.pvc.skillsEnumType.name,
      );

      final again = sink.constructs(
        roomId: '!e2e:pangea.localhost',
        eventId: '\$e2e',
      );
      _check(
        'asking twice is not a recount',
        again.length == uses.length,
        '${uses.length} then ${again.length}',
      );

      print('\n${uses.length} construct uses, language ${sink.langCode}');
      print('provider calls: $_calls');
      print(
        _failures == 0 ? '\nALL CHECKS PASSED' : '\n$_failures CHECK(S) FAILED',
      );
      expect(_failures, 0, reason: 'see the FAIL lines above');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

var _failures = 0;
void _check(String what, bool ok, String detail) {
  print('${ok ? 'ok  ' : 'FAIL'} $what${ok ? '' : ' — $detail'}');
  if (!ok) _failures++;
}
