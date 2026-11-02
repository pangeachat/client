import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_audio_coverage.dart';
import 'package:fluffychat/features/dosage/dosage_audio_event.dart';
import 'package:fluffychat/features/dosage/dosage_audio_signals.dart';
import 'package:fluffychat/features/dosage/dosage_signals_repo.dart';
import 'package:fluffychat/features/dosage/dosage_voice_message.dart';

/// The client-reported voice-message duration, end to end.
///
/// The one non-negotiable pinned here is old-server safety: `voice_messages`
/// reaches the wire ONLY behind the capability flag, because the field's
/// `extra="forbid"` ingest 422s an unknown key and takes the sibling playback +
/// coverage lanes down with it. The rest pins that the duration DOES travel when
/// the flag is on, keyed by the stable `m.audio` id so the server dedups, that a
/// full batch of all three lists still fits the route's 413 cap, and that the
/// send path never waits on any of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mxid = '@learner:example.org';
  const token = 'syt_student_token';
  const roomId = '!room:example.org';
  const msgId = '\$evt:example.org';

  late DateTime clock;
  var seq = 0;

  void loadFlags({required bool voice}) {
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': 'https://bff.test.example',
        if (voice) 'DOSAGE_VOICE_MESSAGES_ENABLED': 'true',
      },
    );
  }

  DosageVoiceMessage voice({
    String id = msgId,
    String room = roomId,
    int durationMs = 4200,
    DateTime? ts,
  }) => DosageVoiceMessage(
    msgId: id,
    roomId: room,
    durationMs: durationMs,
    ts: ts ?? DateTime.utc(2026, 8, 19, 12),
  );

  DosageAudioCoverage coverage() => DosageAudioCoverage(
    coverageId: 'cov-${seq++}',
    category: DosageCoverageCategory.peer,
    periodStart: DateTime.utc(2026, 8, 19, 12),
    periodEnd: DateTime.utc(2026, 8, 19, 12, 5),
  );

  DosageAudioEvent playback() => DosageAudioEvent.fromPlayback(
    playbackId: 'pb-${seq++}',
    roomId: roomId,
    category: DosageListeningCategory.peer,
    elapsed: const Duration(seconds: 3),
    endedAt: clock,
  );

  /// Captures every posted body; answers 202 with the coverage count the buffer
  /// reads back to bank its periods.
  MockClient recorder(List<Map<String, dynamic>> sink) =>
      MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        sink.add(body);
        return http.Response(
          jsonEncode({
            'status': 'accepted',
            'coverage': (body['coverage'] as List).length,
          }),
          202,
        );
      });

  /// A transport that hangs forever — anything that awaited it would hang the
  /// test rather than fail an assertion, which is the proof nothing awaited it.
  http.Client hangingClient() =>
      MockClient((_) => Completer<http.Response>().future);

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('dosage_vm_ingest');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (m) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() {
    clock = DateTime.utc(2026, 8, 19, 12);
    seq = 0;
    loadFlags(voice: true);
    DosageAudioBuffer.debugResetAccounts();
  });

  tearDown(DosageAudioBuffer.debugResetAccounts);

  group('postAudioSignals wire', () {
    test(
      'flag ON: voice_messages travels with the exact four-key shape',
      () async {
        Map<String, dynamic>? sent;
        final client = MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'coverage': 0}), 202);
        });

        final result = await DosageSignalsRepo.postAudioSignals(
          events: const [],
          coverage: const [],
          voiceMessages: [
            voice(id: '\$abc:s', room: '!dm:s', durationMs: 4200),
          ],
          accessToken: token,
          client: client,
        );

        expect(result.delivered, isTrue);
        final vms = sent!['voice_messages'] as List;
        expect(vms, hasLength(1));
        expect(vms.single, {
          'msg_id': '\$abc:s',
          'room_id': '!dm:s',
          'duration_ms': 4200,
          'ts': '2026-08-19T12:00:00.000Z',
        });
      },
    );

    test(
      'flag OFF: voice_messages is OMITTED even when passed (old-server safe)',
      () async {
        loadFlags(voice: false);
        Map<String, dynamic>? sent;
        final client = MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'coverage': 1}), 202);
        });

        // A valid coverage keeps the post from being skipped by the empty-guard, so
        // this really exercises the body the server would see.
        await DosageSignalsRepo.postAudioSignals(
          events: const [],
          coverage: [coverage()],
          voiceMessages: [voice()],
          accessToken: token,
          client: client,
        );

        expect(sent, isNotNull);
        expect(
          sent!.containsKey('voice_messages'),
          isFalse,
          reason:
              'an older server 422s an unknown key and drops the whole batch',
        );
        expect(sent!.keys.toSet(), {'events', 'coverage'});
      },
    );

    test(
      'flag ON but the batch has no voice messages -> key omitted, not empty',
      () async {
        Map<String, dynamic>? sent;
        final client = MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'coverage': 1}), 202);
        });
        await DosageSignalsRepo.postAudioSignals(
          events: const [],
          coverage: [coverage()],
          accessToken: token,
          client: client,
        );
        expect(sent!.containsKey('voice_messages'), isFalse);
      },
    );

    test(
      'an out-of-bound row is dropped; a valid sibling still ships',
      () async {
        Map<String, dynamic>? sent;
        final client = MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'coverage': 0}), 202);
        });
        await DosageSignalsRepo.postAudioSignals(
          events: const [],
          coverage: const [],
          voiceMessages: [
            voice(id: '\$good:s', durationMs: 5000),
            voice(
              id: '\$bad:s',
              durationMs: DosageVoiceMessage.maxDurationMs + 1,
            ),
          ],
          accessToken: token,
          client: client,
        );
        final vms = (sent!['voice_messages'] as List)
            .cast<Map<String, dynamic>>();
        expect(vms.map((v) => v['msg_id']), ['\$good:s']);
      },
    );

    test(
      'a voice-only batch (no events, no coverage) still posts when on',
      () async {
        Map<String, dynamic>? sent;
        final client = MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'coverage': 0}), 202);
        });
        final result = await DosageSignalsRepo.postAudioSignals(
          events: const [],
          coverage: const [],
          voiceMessages: [voice()],
          accessToken: token,
          client: client,
        );
        expect(result.delivered, isTrue);
        expect((sent!['voice_messages'] as List), hasLength(1));
      },
    );

    test('the wire trims voice so a body can never exceed the 413 cap', () async {
      // A direct caller that ignores the buffer's budget must still not build a
      // 413-bound body. Voice is trimmed (never events/coverage) to fit 200.
      Map<String, dynamic>? sent;
      final client = MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'coverage': 0}), 202);
      });
      final many = List.generate(400, (i) => voice(id: '\$v$i:s'));
      await DosageSignalsRepo.postAudioSignals(
        events: const [],
        coverage: const [],
        voiceMessages: many,
        accessToken: token,
        client: client,
      );
      final e = (sent!['events'] as List).length;
      final c = (sent!['coverage'] as List).length;
      final v = (sent!['voice_messages'] as List).length;
      expect(e + c + v, lessThanOrEqualTo(200));
      expect(
        v,
        200,
        reason: 'all 200 slots go to voice when nothing else uses them',
      );
    });

    test(
      'a 422 on an old server retries the siblings WITHOUT the voice field',
      () async {
        // The mis-enabled-flag worst case: a pre-#150 server 422s any body carrying
        // voice_messages, which would take the already-live playback + coverage
        // lanes down with it. The retry strips the field so those still land.
        final bodies = <Map<String, dynamic>>[];
        final client = MockClient((req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          bodies.add(body);
          if (body.containsKey('voice_messages')) {
            return http.Response('unknown field voice_messages', 422);
          }
          return http.Response(jsonEncode({'coverage': 1}), 202);
        });
        final result = await DosageSignalsRepo.postAudioSignals(
          events: const [],
          coverage: [coverage()],
          voiceMessages: [voice()],
          accessToken: token,
          client: client,
        );
        expect(
          result.delivered,
          isTrue,
          reason: 'the siblings must still land',
        );
        expect(bodies, hasLength(2));
        expect(bodies.first.containsKey('voice_messages'), isTrue);
        expect(bodies.last.containsKey('voice_messages'), isFalse);
        expect((bodies.last['coverage'] as List), hasLength(1));
      },
    );
  });

  group('through the buffer', () {
    test(
      'recordVoiceMessage rides the heartbeat batch, keyed by the given id',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final buffer = DosageAudioBuffer(
          now: () => clock,
          httpClient: recorder(bodies),
        );

        // Same path chat.dart takes: primitives in, the stable m.audio id as msgId.
        DosageAudioSignals.recordVoiceMessage(
          msgId: msgId,
          roomId: roomId,
          durationMs: 7000,
          userId: mxid,
          accessToken: token,
          buffer: buffer,
        );
        clock = clock.add(const Duration(minutes: 1));
        await buffer.flush(drainAll: true, accessToken: token);

        expect(bodies, hasLength(1));
        final vms = (bodies.single['voice_messages'] as List)
            .cast<Map<String, dynamic>>();
        expect(vms, hasLength(1));
        expect(vms.single['msg_id'], msgId);
        expect(vms.single['room_id'], roomId);
        expect(vms.single['duration_ms'], 7000);
      },
    );

    test('capability flag OFF: recordVoiceMessage buffers nothing', () async {
      loadFlags(voice: false);
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: recorder(<Map<String, dynamic>>[]),
      );
      DosageAudioSignals.recordVoiceMessage(
        msgId: msgId,
        roomId: roomId,
        durationMs: 7000,
        userId: mxid,
        accessToken: token,
        buffer: buffer,
      );
      expect(buffer.bufferedVoiceMessages, isEmpty);
    });

    test('the funnel drops garbage before it can reach a batch', () {
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: hangingClient(),
      );
      DosageAudioSignals.recordVoiceMessage(
        msgId: '',
        roomId: roomId,
        durationMs: 3000,
        userId: mxid,
        accessToken: token,
        buffer: buffer,
      );
      DosageAudioSignals.recordVoiceMessage(
        msgId: msgId,
        roomId: '',
        durationMs: 3000,
        userId: mxid,
        accessToken: token,
        buffer: buffer,
      );
      DosageAudioSignals.recordVoiceMessage(
        msgId: msgId,
        roomId: roomId,
        durationMs: -1,
        userId: mxid,
        accessToken: token,
        buffer: buffer,
      );
      DosageAudioSignals.recordVoiceMessage(
        msgId: msgId,
        roomId: roomId,
        durationMs: DosageVoiceMessage.maxDurationMs + 1,
        userId: mxid,
        accessToken: token,
        buffer: buffer,
      );
      expect(buffer.bufferedVoiceMessages, isEmpty);
    });

    test('events + voice messages + coverage never exceed the route 413 cap', () async {
      // The worst real case: the shared observation budget filled with a MIX of
      // voice messages and events, sealed at its longest interval across a
      // midnight so coverage is maximal. Every posted body must still fit.
      clock = DateTime.utc(2026, 1, 1, 23, 50);
      const voiceCount = 10;
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: recorder(bodies),
      );
      buffer.start();
      // Voice messages FIRST, then a FULL event budget on top. If the seal trigger
      // did not count voice messages against the shared budget, this batch would
      // carry maxEventsPerBatch events + these voice rows + coverage and 413 — so
      // this arrangement is what makes the shared-budget arithmetic load-bearing.
      for (var i = 0; i < voiceCount; i++) {
        buffer.recordVoiceMessage(voice(id: '\$v$i:s'), accessToken: token);
      }
      for (var i = 0; i < DosageAudioBuffer.maxEventsPerBatch; i++) {
        buffer.record(playback(), accessToken: token);
      }
      clock = clock.add(DosageAudioBuffer.maxObservedGap);
      await buffer.flush(drainAll: true, accessToken: token);

      expect(bodies, isNotEmpty);
      var sawVoice = false;
      for (final body in bodies) {
        final events = (body['events'] as List).length;
        final cov = (body['coverage'] as List).length;
        final vms = (body['voice_messages'] as List?)?.length ?? 0;
        if (vms > 0) sawVoice = true;
        expect(
          events + cov + vms,
          lessThanOrEqualTo(DosageAudioBuffer.maxItemsPerBatch),
          reason: 'a body the route 413s loses that whole period',
        );
      }
      expect(sawVoice, isTrue, reason: 'the voice messages must actually ship');
    });
  });

  group('the send path never waits on telemetry', () {
    test(
      'recordVoiceMessage returns synchronously against a hung transport',
      () {
        final buffer = DosageAudioBuffer(
          now: () => clock,
          httpClient: hangingClient(),
        );
        // If this awaited the POST it would hang forever (the client never
        // resolves). It returns, and the row is buffered for a later flush.
        DosageAudioSignals.recordVoiceMessage(
          msgId: msgId,
          roomId: roomId,
          durationMs: 3000,
          userId: mxid,
          accessToken: token,
          buffer: buffer,
        );
        expect(buffer.bufferedVoiceMessages, hasLength(1));
      },
    );
  });
}
