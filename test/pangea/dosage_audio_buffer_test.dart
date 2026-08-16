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
import 'package:fluffychat/features/dosage/dosage_audio_event.dart';
import 'package:fluffychat/features/dosage/dosage_signals_repo.dart';

/// The retry buffer ([DosageAudioBuffer]).
///
/// Listening is the one dosage signal with NO Matrix artefact behind it: a lost
/// POST is an observation gone forever, which is why this lane retries where the
/// others fire and forget. What the suite pins is that retrying stays bounded,
/// that the coverage declaration and the events it licenses are never separable,
/// and that an absent route — the NORMAL state until the server ships — is inert.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const token = 'syt_student_token';
  const roomId = '!room:example.org';

  late DateTime clock;

  DosageAudioEvent playback([
    DosageListeningCategory category = DosageListeningCategory.peer,
  ]) => DosageAudioEvent.fromPlayback(
    playbackId: 'id-${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
    roomId: roomId,
    category: category,
    elapsed: const Duration(seconds: 3),
    endedAt: clock,
  );

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('dosage_audio_buf');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (m) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() {
    clock = DateTime.utc(2026, 1, 1, 12);
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': 'https://bff.test.example',
      },
    );
    DosageAudioBuffer.debugResetAccounts();
  });

  tearDown(DosageAudioBuffer.debugResetAccounts);

  group('coverage declaration', () {
    test('every flush declares ALL FOUR categories, even with no audio', () {
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(bodies),
      );

      buffer.start();
      clock = clock.add(const Duration(minutes: 5));
      return buffer.flush(accessToken: token).then((_) {
        expect(
          bodies,
          hasLength(1),
          reason:
              'silence is an observation: without a declaration the server '
              'cannot tell "heard nothing" from "app too old to measure"',
        );
        final coverage = (bodies.single['coverage'] as List)
            .cast<Map<String, dynamic>>();
        expect(coverage.map((c) => c['category']).toSet(), {
          'peer',
          'auto_read',
          'tap_read',
          'voice_send',
        });
        expect((bodies.single['events'] as List), isEmpty);
        for (final c in coverage) {
          expect(c['period_start'], '2026-01-01T12:00:00.000Z');
          expect(c['period_end'], '2026-01-01T12:05:00.000Z');
        }
      });
    });

    test('periods are contiguous across flushes — no unclaimed gap', () async {
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(bodies),
      );
      buffer.start();
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);

      final firstEnd = _coverageOf(bodies[0], 'peer')['period_end'];
      final secondStart = _coverageOf(bodies[1], 'peer')['period_start'];
      expect(
        secondStart,
        firstEnd,
        reason: 'a gap between periods is an hour nobody declared',
      );
    });

    test('the period a build never observed is NEVER claimed', () async {
      // The buffer is created but never started and never used: it must not
      // retroactively declare the time before it existed.
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(bodies),
      );
      clock = clock.add(const Duration(hours: 3));
      await buffer.flush(accessToken: token);
      expect(bodies, isEmpty);
    });

    test('voice_send is WITHHELD when an envelope was lost', () async {
      // The one coverage category whose evidence rides a different route. A
      // declaration that landed while its envelope did not would license the
      // server to serve a confident speaking ZERO for a message it never saw.
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(bodies),
      );
      buffer.start();
      buffer.noteVoiceSendPending();
      buffer.noteVoiceSendSettled(delivered: false);
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);

      final declared = (bodies.single['coverage'] as List)
          .cast<Map<String, dynamic>>()
          .map((c) => c['category'])
          .toSet();
      expect(declared, {'peer', 'auto_read', 'tap_read'});
      expect(
        declared,
        isNot(contains('voice_send')),
        reason: 'we cannot vouch for that period, so we do not claim it',
      );
    });

    test(
      'voice_send is WITHHELD while an envelope is still unconfirmed',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final buffer = DosageAudioBuffer(
          now: () => clock,
          httpClient: _recorder(bodies),
        );
        buffer.start();
        buffer.noteVoiceSendPending();
        clock = clock.add(const Duration(minutes: 5));
        await buffer.flush(accessToken: token);

        expect(
          (bodies.single['coverage'] as List).cast<Map<String, dynamic>>().map(
            (c) => c['category'],
          ),
          isNot(contains('voice_send')),
          reason: 'in flight is UNKNOWN, not delivered',
        );
      },
    );

    test(
      'voice_send is declared once its envelopes are acknowledged',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final buffer = DosageAudioBuffer(
          now: () => clock,
          httpClient: _recorder(bodies),
        );
        buffer.start();
        buffer.noteVoiceSendPending();
        buffer.noteVoiceSendSettled(delivered: true);
        clock = clock.add(const Duration(minutes: 5));
        await buffer.flush(accessToken: token);

        expect(
          (bodies.single['coverage'] as List)
              .cast<Map<String, dynamic>>()
              .map((c) => c['category'])
              .toSet(),
          {'peer', 'auto_read', 'tap_read', 'voice_send'},
        );
      },
    );

    test('a loss darkens only the period it is reported in', () async {
      // The flag is per period, not sticky: one lost envelope must not withhold
      // speaking for the rest of the session.
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(bodies),
      );
      buffer.start();
      buffer.noteVoiceSendPending();
      buffer.noteVoiceSendSettled(delivered: false);
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);

      expect(
        (bodies[1]['coverage'] as List).cast<Map<String, dynamic>>().map(
          (c) => c['category'],
        ),
        contains('voice_send'),
      );
    });

    test('events and their coverage travel in ONE body', () async {
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(bodies),
      );
      buffer.start();
      buffer.record(playback(), accessToken: token);
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);

      // If they could arrive separately, a period whose events were lost while
      // its declaration landed would have the server serve an undercount as a
      // confident total.
      expect((bodies.single['events'] as List), hasLength(1));
      expect((bodies.single['coverage'] as List), hasLength(4));
    });
  });

  group('retry', () {
    test('an undelivered batch is kept and redelivered verbatim', () async {
      var fail = true;
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: MockClient((req) async {
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response('', fail ? 503 : 202);
        }),
      );
      buffer.start();
      buffer.record(playback(), accessToken: token);
      clock = clock.add(const Duration(minutes: 5));

      await buffer.flush(accessToken: token);
      expect(buffer.pendingBatches, hasLength(1));

      fail = false;
      // First retry waits one tick of backoff.
      await buffer.flush(accessToken: token);
      await buffer.flush(accessToken: token);
      expect(buffer.pendingBatches, isEmpty);

      // Redelivered verbatim: the idempotency key is unchanged, so the server's
      // ON CONFLICT DO NOTHING makes the retry a no-op rather than a duplicate.
      final ids = bodies
          .map((b) => (b['events'] as List).single as Map<String, dynamic>)
          .map((e) => e['playback_id'])
          .toSet();
      expect(ids, hasLength(1));
    });

    test('a delivered batch is never sent again', () async {
      var posts = 0;
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: MockClient((_) async {
          posts++;
          return http.Response('', 202);
        }),
      );
      buffer.start();
      buffer.record(playback(), accessToken: token);
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);
      expect(posts, 1);

      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);
      // A second flush declares the NEW period; it must not resend the old one.
      expect(posts, 2);
      expect(buffer.pendingBatches, isEmpty);
    });

    test('no bearer yet: batches are held, not spent on an attempt', () async {
      var posts = 0;
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: MockClient((_) async {
          posts++;
          return http.Response('', 202);
        }),
      );
      buffer.start();
      buffer.record(playback(), accessToken: null);
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush();

      expect(posts, 0);
      expect(buffer.pendingBatches, hasLength(1));
      expect(buffer.pendingBatches.single.attempts, 0);

      await buffer.flush(accessToken: token);
      expect(posts, 1);
    });

    test('a teardown drain is NOT swallowed by an in-flight heartbeat', () async {
      // disposeAccount removes the buffer and then drains. If the drain-all
      // coalesced onto a heartbeat drain already in flight, teardown would wait
      // on a pass that sends only maxSendsPerFlush and honours backoff, and the
      // buffer would then be dropped with batches still in it.
      final gate = Completer<http.Response>();
      var gated = true;
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: MockClient((_) {
          if (gated) return gate.future;
          return Future.value(http.Response('', 202));
        }),
      );
      buffer.start();

      // More pending batches than one ordinary pass can send. Built with no
      // bearer, so each flush seals a batch and holds it without attempting it.
      for (var i = 0; i < DosageAudioBuffer.maxSendsPerFlush + 3; i++) {
        buffer.record(playback(), accessToken: null);
        clock = clock.add(const Duration(minutes: 5));
        await buffer.flush();
      }
      expect(
        buffer.pendingBatches.length,
        greaterThan(DosageAudioBuffer.maxSendsPerFlush),
      );

      final heartbeat = buffer.flush(accessToken: token);
      await pumpEventQueue();

      final teardown = buffer.flush(drainAll: true, accessToken: token);
      gated = false;
      gate.complete(http.Response('', 202));
      await heartbeat;
      await teardown;

      expect(
        buffer.pendingBatches,
        isEmpty,
        reason: 'the teardown pass ran its own drain rather than coalescing',
      );
    });

    test('concurrent flushes coalesce onto one drain', () async {
      var posts = 0;
      final gate = Completer<http.Response>();
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: MockClient((_) {
          posts++;
          return gate.future;
        }),
      );
      buffer.start();
      buffer.record(playback(), accessToken: token);
      clock = clock.add(const Duration(minutes: 5));

      final a = buffer.flush(accessToken: token);
      final b = buffer.flush(accessToken: token);
      await pumpEventQueue();
      expect(
        posts,
        1,
        reason: 'a heartbeat landing on a lifecycle flush must not double-send',
      );
      gate.complete(http.Response('', 202));
      await Future.wait([a, b]);
    });
  });

  group('the bound', () {
    test('pending batches are capped, and the OLDEST is dropped whole', () async {
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      buffer.start();

      // Far more flushes than the cap, all against an absent route.
      for (var i = 0; i < DosageAudioBuffer.maxPendingBatches * 4; i++) {
        buffer.record(playback(), accessToken: token);
        clock = clock.add(const Duration(minutes: 5));
        await buffer.flush(accessToken: token);
      }

      expect(
        buffer.pendingBatches.length,
        lessThanOrEqualTo(DosageAudioBuffer.maxPendingBatches),
        reason: 'silent unbounded growth on a learner device is not acceptable',
      );
      expect(buffer.droppedBatches, greaterThan(0));

      // What is dropped is a WHOLE batch — its events AND the coverage that
      // licensed them. The server then sees an undeclared period and withholds,
      // rather than serving the surviving events as a total.
      for (final batch in buffer.pendingBatches) {
        expect(batch.coverage, hasLength(4));
      }
    });

    test(
      'a batch is abandoned after maxAttempts, taking its coverage',
      () async {
        var posts = 0;
        final buffer = DosageAudioBuffer(
          now: () => clock,
          httpClient: MockClient((_) async {
            posts++;
            return http.Response('', 500);
          }),
        );
        buffer.start();
        buffer.record(playback(), accessToken: token);
        clock = clock.add(const Duration(minutes: 5));

        // Enough ticks to exhaust the 1/2/4/8 backoff schedule.
        for (var i = 0; i < 40; i++) {
          await buffer.flush(accessToken: token);
        }

        expect(buffer.pendingBatches, isEmpty);
        expect(buffer.droppedBatches, greaterThanOrEqualTo(1));
        expect(
          posts,
          lessThanOrEqualTo(DosageAudioBuffer.maxAttempts + 2),
          reason: 'retry stops; it does not hammer an absent route forever',
        );
      },
    );

    test('the accumulator seals at the server batch cap', () {
      final buffer = DosageAudioBuffer(now: () => clock);
      buffer.start();
      for (var i = 0; i < DosageAudioBuffer.maxEventsPerBatch + 5; i++) {
        buffer.record(playback(), accessToken: token);
      }
      expect(
        buffer.bufferedEvents.length,
        lessThanOrEqualTo(DosageAudioBuffer.maxEventsPerBatch),
        reason: 'a body the route would 413 is never built',
      );
      expect(buffer.pendingBatches, hasLength(1));
    });
  });

  group('inert while the surface does not exist', () {
    test(
      '404 everywhere: nothing throws, nothing surfaces, nothing grows',
      () async {
        final buffer = DosageAudioBuffer(
          now: () => clock,
          httpClient: MockClient((_) async => http.Response('Not Found', 404)),
        );
        buffer.start();

        Object? escaped;
        await runZonedGuarded(() async {
          for (var i = 0; i < 60; i++) {
            buffer.record(playback(), accessToken: token);
            clock = clock.add(const Duration(minutes: 5));
            await buffer.flush(accessToken: token);
          }
          await buffer.flush(drainAll: true, accessToken: token);
        }, (e, _) => escaped = e);

        expect(
          escaped,
          isNull,
          reason: 'an absent route is inert, not an error',
        );
        expect(
          buffer.pendingBatches.length,
          lessThanOrEqualTo(DosageAudioBuffer.maxPendingBatches),
        );
      },
    );

    test(
      'a transport that throws is swallowed and the batch is kept',
      () async {
        var throwing = true;
        final buffer = DosageAudioBuffer(
          now: () => clock,
          httpClient: MockClient((_) async {
            if (throwing) throw const SocketException('offline');
            return http.Response('', 202);
          }),
        );
        buffer.start();
        buffer.record(playback(), accessToken: token);
        clock = clock.add(const Duration(minutes: 5));

        await expectLater(buffer.flush(accessToken: token), completes);
        expect(buffer.pendingBatches, hasLength(1));

        throwing = false;
        await buffer.flush(accessToken: token);
        await buffer.flush(accessToken: token);
        expect(buffer.pendingBatches, isEmpty);
      },
    );

    test('dark: nothing is buffered and nothing is posted', () async {
      dotenv.testLoad(mergeWith: {'DOSAGE_SIGNALS_ENABLED': 'false'});
      var posts = 0;
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: MockClient((_) async {
          posts++;
          return http.Response('', 202);
        }),
      );
      buffer.start();
      buffer.record(playback(), accessToken: token);
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);

      expect(buffer.periodStart, isNull);
      expect(buffer.bufferedEvents, isEmpty);
      expect(posts, 0);
    });
  });

  group('never keeps a user waiting', () {
    test('a hung endpoint releases the caller at the flush deadline', () async {
      // Teardown and logout AWAIT a flush. Until the ingest route ships, an
      // unreachable endpoint is the normal case — a learner logging out must not
      // sit behind it.
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: MockClient((_) => Completer<http.Response>().future),
      );
      buffer.start();
      buffer.record(playback(), accessToken: token);
      clock = clock.add(const Duration(minutes: 5));

      var released = false;
      final flush = buffer
          .flush(drainAll: true, accessToken: token)
          .then((_) => released = true);

      await Future<void>.delayed(
        DosageAudioBuffer.flushDeadline + const Duration(milliseconds: 200),
      );
      expect(
        released,
        isTrue,
        reason: 'the caller is released even though the POST never resolved',
      );
      await flush;
    });
  });

  group('the repo contract', () {
    test('only a 2xx counts as delivered', () async {
      for (final status in [200, 202, 204]) {
        expect(
          await DosageSignalsRepo.postAudioSignals(
            events: [playback()],
            coverage: const [],
            accessToken: token,
            client: MockClient((_) async => http.Response('', status)),
          ),
          isTrue,
        );
      }
      for (final status in [400, 401, 404, 413, 422, 500, 503]) {
        expect(
          await DosageSignalsRepo.postAudioSignals(
            events: [playback()],
            coverage: const [],
            accessToken: token,
            client: MockClient((_) async => http.Response('', status)),
          ),
          isFalse,
          reason: '$status is undelivered, so the batch is retried',
        );
      }
    });

    test('carries no sender: identity is bound from the bearer', () async {
      Map<String, dynamic>? body;
      await DosageSignalsRepo.postAudioSignals(
        events: [playback()],
        coverage: const [],
        accessToken: token,
        client: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(req.headers['Authorization'], 'Bearer $token');
          return http.Response('', 202);
        }),
      );
      expect(body!.keys.toSet(), {'events', 'coverage'});
      final event = (body!['events'] as List).single as Map<String, dynamic>;
      expect(event.keys, isNot(contains('sender')));
    });

    test('a body that says nothing is not sent', () async {
      var posts = 0;
      final client = MockClient((_) async {
        posts++;
        return http.Response('', 202);
      });
      expect(
        await DosageSignalsRepo.postAudioSignals(
          events: const [],
          coverage: const [],
          accessToken: token,
          client: client,
        ),
        isFalse,
      );
      expect(posts, 0);
    });
  });
}

int _seq = 0;

MockClient _recorder(List<Map<String, dynamic>> sink) =>
    MockClient((req) async {
      sink.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('', 202);
    });

Map<String, dynamic> _coverageOf(Map<String, dynamic> body, String category) =>
    (body['coverage'] as List).cast<Map<String, dynamic>>().firstWhere(
      (c) => c['category'] == category,
    );
