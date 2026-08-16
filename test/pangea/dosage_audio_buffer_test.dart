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
    test('every flush declares ALL FIVE categories, even with no audio', () {
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
          'toolbar_read',
          'voice_send',
        });
        expect((bodies.single['events'] as List), isEmpty);
        for (final c in coverage) {
          expect(c['period_start'], '2026-01-01T12:00:00.000Z');
          expect(c['period_end'], '2026-01-01T12:05:00.000Z');
        }
      });
    });

    test('a period EXTENDS across flushes rather than minting a new one', () async {
      // The defect this replaced: a fresh period_start every seal banked five new
      // rows per flush — sixty an hour — and walked into the server's per-day
      // coverage cap after three or four hours of app-open time, after which the
      // learner's listening counters withheld for the rest of the UTC day.
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(bodies),
      );
      buffer.start();
      final opened = clock;
      for (var i = 0; i < 6; i++) {
        clock = clock.add(const Duration(minutes: 5));
        await buffer.flush(accessToken: token);
      }

      expect(bodies, hasLength(6));
      // The server banks one row per (category, period_start). Six flushes of
      // five categories must still be five rows, not thirty.
      final rows = bodies
          .expand((b) => (b['coverage'] as List).cast<Map<String, dynamic>>())
          .map((c) => '${c['category']}@${c['period_start']}')
          .toSet();
      expect(
        rows,
        hasLength(DosageCoverageCategory.values.length),
        reason: 'one banked row per category, lengthened — not one per seal',
      );

      final peer = bodies
          .map((b) => _coverageOf(b, 'peer'))
          .toList(growable: false);
      for (final declaration in peer) {
        expect(declaration['period_start'], opened.toIso8601String());
      }
      final ends = peer.map((c) => DateTime.parse(c['period_end'] as String));
      expect(
        ends.toList(),
        orderedEquals([
          for (var i = 1; i <= 6; i++)
            opened.add(Duration(minutes: 5 * i)).toUtc(),
        ]),
        reason: 'the end advances; that is the whole extension',
      );
    });

    test('the claimed union covers the observed time exactly', () async {
      // Extending moves the end, which is where a claim can drift off what was
      // watched. What every flush declared, unioned, must be precisely the stretch
      // from the instrument opening to the last seal: no gap nobody declared, and
      // no overlap reaching past what was observed.
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(bodies),
      );
      buffer.start();
      final opened = clock;
      for (var i = 0; i < 5; i++) {
        clock = clock.add(const Duration(minutes: 5));
        buffer.record(playback(), accessToken: token);
        await buffer.flush(accessToken: token);
      }
      final lastSeal = clock;

      final merged = _union(_periodsFor(bodies, 'peer'));
      expect(
        merged,
        hasLength(1),
        reason: 'a second interval would be a stretch nobody declared',
      );
      expect(merged.single.start, opened.toUtc());
      expect(merged.single.end, lastSeal.toUtc());
    });

    test('a fresh process never extends a period it did not observe', () async {
      // The buffer is in-memory, so a restart forgets both the observation cursor
      // and the anchor. That is the rollover rule for a restart: a period whose
      // start is gone cannot be lengthened, and the interval while nothing was
      // running is one nobody watched.
      final first = <Map<String, dynamic>>[];
      final before = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(first),
      );
      before.start();
      clock = clock.add(const Duration(minutes: 5));
      await before.flush(accessToken: token);

      // The process dies here; three hours later a new one starts.
      clock = clock.add(const Duration(hours: 3));
      final restartedAt = clock;
      final second = <Map<String, dynamic>>[];
      final after = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(second),
      );
      after.start();
      clock = clock.add(const Duration(minutes: 5));
      await after.flush(accessToken: token);

      expect(
        _coverageOf(second.single, 'peer')['period_start'],
        restartedAt.toIso8601String(),
        reason: 'the three hours the app was not running are not claimed',
      );
      final merged = _union([
        ..._periodsFor(first, 'peer'),
        ..._periodsFor(second, 'peer'),
      ]);
      expect(
        merged,
        hasLength(2),
        reason: 'the gap between the two processes stays a gap',
      );
    });

    test('a period does not extend across a UTC midnight', () async {
      // The server buckets its per-day coverage cap on period_start's day, so one
      // row spanning days would be counted against a day it barely touches — and
      // an open period that never rolls has no bound at all.
      clock = DateTime.utc(2026, 1, 1, 23, 57);
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(bodies),
      );
      buffer.start();
      final opened = clock;
      final midnight = DateTime.utc(2026, 1, 2);

      clock = DateTime.utc(2026, 1, 2, 0, 2);
      await buffer.flush(accessToken: token);
      clock = DateTime.utc(2026, 1, 2, 0, 7);
      await buffer.flush(accessToken: token);

      final crossing = (bodies[0]['coverage'] as List)
          .cast<Map<String, dynamic>>()
          .where((c) => c['category'] == 'peer')
          .toList();
      expect(
        crossing,
        hasLength(2),
        reason: 'the seal that crossed midnight declares one row per day',
      );
      expect(crossing[0]['period_start'], opened.toIso8601String());
      expect(
        crossing[0]['period_end'],
        midnight.toIso8601String(),
        reason: 'and they abut exactly, so the union has no gap',
      );
      expect(crossing[1]['period_start'], midnight.toIso8601String());

      // The next seal extends the NEW day's row, not the old one.
      expect(
        _coverageOf(bodies[1], 'peer')['period_start'],
        midnight.toIso8601String(),
      );
      expect(
        _union(_periodsFor(bodies, 'peer')),
        hasLength(1),
        reason: 'rolling at the boundary must not open a hole at it',
      );
    });

    test('a 202 over a FAILED WRITE does not extend anything', () async {
      // The route answers 202 for any well-formed batch even when its database
      // write failed, and reports the rows it actually wrote. Treating the 202 as
      // the acknowledgement would have the next seal lengthen a row the server
      // never held — covering the failed batch's interval without its events.
      final bodies = <Map<String, dynamic>>[];
      var writing = false;
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: MockClient((req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          bodies.add(body);
          return http.Response(
            jsonEncode({
              'status': 'accepted',
              'playbacks': writing ? (body['events'] as List).length : 0,
              'coverage': writing ? (body['coverage'] as List).length : 0,
            }),
            202,
          );
        }),
      );

      buffer.start();
      final swallowedFrom = clock;
      clock = clock.add(const Duration(minutes: 5));
      final swallowedTo = clock;
      await buffer.flush(accessToken: token);
      expect(
        buffer.pendingBatches,
        isEmpty,
        reason: 'a 202 is still a 202: the batch is not retried',
      );

      writing = true;
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);

      expect(
        _coverageOf(bodies[1], 'peer')['period_start'],
        swallowedTo.toIso8601String(),
        reason: 'a fresh period after the hole, not an extension across it',
      );
      for (final period in _periodsFor([bodies[1]], 'peer')) {
        expect(
          period.start.isBefore(swallowedTo.toUtc()) &&
              period.end.isAfter(swallowedFrom.toUtc()),
          isFalse,
          reason: 'the swallowed interval stays uncovered',
        );
      }
    });

    test('a PARTIAL write does not extend anything either', () async {
      // The count is an aggregate — rows written, not which ones. The server drops
      // individual declarations that hit its per-day coverage cap, so a batch of
      // five that reports one written leaves four unaccounted for. Banking on that
      // would anchor rows the server does not hold.
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: MockClient((req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          bodies.add(body);
          final declared = (body['coverage'] as List).length;
          return http.Response(
            jsonEncode({
              'status': 'accepted',
              'playbacks': (body['events'] as List).length,
              // One of the five landed; the rest hit the daily cap.
              'coverage': declared > 1 ? 1 : declared,
            }),
            202,
          );
        }),
      );

      buffer.start();
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);
      final secondStart = clock;
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);

      expect(
        _coverageOf(bodies[1], 'peer')['period_start'],
        secondStart.toIso8601String(),
        reason: 'a partial count proves nothing about any particular row',
      );
    });

    test('an unreadable response is not an acknowledgement', () async {
      // Anything the client cannot read as a written-row count — an empty body, a
      // proxy's own page, a shape that changed — resolves to "not acknowledged".
      // The cost is one extra coverage row per flush; the alternative is claiming
      // a period on the strength of a response nobody could parse.
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: MockClient((req) async {
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response('<html>accepted</html>', 202);
        }),
      );
      buffer.start();
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);
      final secondStart = clock;
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);

      expect(
        _coverageOf(bodies[1], 'peer')['period_start'],
        secondStart.toIso8601String(),
      );
      expect(
        _union(_periodsFor(bodies, 'peer')),
        hasLength(1),
        reason: 'still contiguous — the periods abut, they just do not merge',
      );
    });

    test('a dropped batch takes its interval with it, for good', () async {
      // The bound drops a whole batch — its events AND its declaration together —
      // so the server withholds that stretch. Extending is where that could quietly
      // come undone: a later seal that anchored back past the hole would restore the
      // coverage without the events, leaving a covered period that looks empty. That
      // is the fabricated zero this feature exists to prevent, so no declaration may
      // reach back over an interval the ingest never acknowledged.
      const poisonRoom = '!undeliverable:example.org';
      final delivered = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: MockClient((req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final undeliverable = (body['events'] as List)
              .cast<Map<String, dynamic>>()
              .any((e) => e['room_id'] == poisonRoom);
          if (undeliverable) return http.Response('', 503);
          delivered.add(body);
          return http.Response('', 202);
        }),
      );

      buffer.start();
      final opened = clock;
      buffer.record(
        DosageAudioEvent.fromPlayback(
          playbackId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          roomId: poisonRoom,
          category: DosageListeningCategory.peer,
          elapsed: const Duration(seconds: 3),
          endedAt: clock,
        ),
        accessToken: token,
      );
      clock = clock.add(const Duration(minutes: 5));
      final lost = clock;
      await buffer.flush(accessToken: token);

      // Every later flush delivers; the first batch exhausts its attempts and is
      // dropped, so [opened, lost] is an interval nobody ever acknowledged.
      for (var i = 0; i < 40; i++) {
        clock = clock.add(const Duration(minutes: 5));
        await buffer.flush(accessToken: token);
      }
      expect(buffer.pendingBatches, isEmpty);
      expect(buffer.droppedBatches, greaterThanOrEqualTo(1));
      expect(delivered, isNotEmpty);

      for (final period in _periodsFor(delivered, 'peer')) {
        expect(
          period.start.isBefore(lost.toUtc()) &&
              period.end.isAfter(opened.toUtc()),
          isFalse,
          reason:
              'nothing delivered may overlap the dropped batch\'s interval — its '
              'events are gone, so covering it would serve a confident zero',
        );
      }
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

    test('a period opens where the instrument is KNOWN to be running', () async {
      // A flush means the buffer is live and reachable by every emit site, so
      // the period may open there — but it opens explicitly, never as a side
      // effect of sealing nothing. The distinction matters because when the
      // period starts is the one fact this class asserts, and it must not depend
      // on when a flush happened to fire.
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(bodies),
      );

      // Never started. Two hours pass before anything flushes.
      clock = clock.add(const Duration(hours: 2));
      await buffer.flush(accessToken: token);
      expect(
        bodies,
        isEmpty,
        reason: 'the two hours before the buffer was reachable are not claimed',
      );
      final opened = buffer.observedFrom;
      expect(opened, isNotNull);

      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);
      expect(
        _coverageOf(bodies.single, 'peer')['period_start'],
        opened!.toIso8601String(),
        reason: 'the declared period starts where the instrument did',
      );
    });

    test(
      'opening a period does not also declare it, on a REAL clock',
      () async {
        // The seal is what puts a period on the wire, so a flush that OPENS a
        // period must not seal it in the same call: the period would be however
        // long two clock reads happened to take. A fixed-clock test cannot see
        // this, so this one uses the real one.
        final bodies = <Map<String, dynamic>>[];
        final buffer = DosageAudioBuffer(httpClient: _recorder(bodies));
        await buffer.flush(accessToken: token);
        expect(
          bodies,
          isEmpty,
          reason: 'a microsecond-long period is noise, not an observation',
        );
      },
    );

    test('a loss survives a seal that declared nothing', () async {
      // The withhold flag is the entire mechanism, so it must outlive a seal
      // that emitted no coverage — otherwise the loss is erased without any
      // period having been withheld for it, and the next period declares
      // voice_send for a message the server never saw.
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(bodies),
      );
      buffer.start();
      buffer.noteVoiceSendPending();
      buffer.noteVoiceSendSettled(delivered: false);
      // An event, so the seal below DOES produce a batch — it just produces one
      // with no coverage in it. That is the case where the flag could be
      // discharged by a seal that declared nothing.
      buffer.record(playback(), accessToken: token);

      // A seal at the same instant the period opened: zero length, so its
      // coverage is all invalid and the batch carries events only.
      await buffer.flush(accessToken: token);
      expect(bodies, hasLength(1));
      expect((bodies.single['coverage'] as List), isEmpty);
      expect((bodies.single['events'] as List), hasLength(1));
      bodies.clear();

      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);
      expect(
        (bodies.single['coverage'] as List).cast<Map<String, dynamic>>().map(
          (c) => c['category'],
        ),
        isNot(contains('voice_send')),
        reason: 'the loss was never discharged, so it must still withhold',
      );
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
      expect(declared, {'peer', 'auto_read', 'tap_read', 'toolbar_read'});
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
          {'peer', 'auto_read', 'tap_read', 'toolbar_read', 'voice_send'},
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
      expect((bodies.single['coverage'] as List), hasLength(5));
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

    test(
      'the period ends when the flush was ASKED FOR, not when it ran',
      () async {
        // A drain can run seconds after its flush — chained behind another pass,
        // or waiting on a slow POST. At teardown the account is tombstoned the
        // moment disposal starts, so sealing inside the drain would claim a
        // period during which every emit site was already recording nothing.
        final bodies = <Map<String, dynamic>>[];
        final gate = Completer<http.Response>();
        var gated = true;
        final buffer = DosageAudioBuffer(
          now: () => clock,
          httpClient: MockClient((req) {
            bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
            if (gated) return gate.future;
            return Future.value(http.Response('', 202));
          }),
        );
        buffer.start();
        buffer.record(playback(), accessToken: token);
        clock = clock.add(const Duration(minutes: 5));

        final first = buffer.flush(accessToken: token);
        await pumpEventQueue();

        // Teardown asks while the first POST is still hanging.
        final askedAt = clock;
        final teardown = buffer.flush(drainAll: true, accessToken: token);
        // The drain only runs much later.
        clock = clock.add(const Duration(minutes: 30));
        gated = false;
        gate.complete(http.Response('', 202));
        await first;
        await teardown;

        final periods = bodies
            .expand((b) => (b['coverage'] as List).cast<Map<String, dynamic>>())
            .map((c) => c['period_end'] as String)
            .toSet();
        expect(
          periods,
          everyElement(isNot(contains('T12:35'))),
          reason: 'no period may end at the drain time, 30 minutes later',
        );
        expect(periods, contains(askedAt.toUtc().toIso8601String()));
      },
    );

    test('an invalidated bearer holds the batches, it does not post', () async {
      // Every production caller reads the account's bearer live. Logout nulls
      // it, and the buffer must treat that as "hold" rather than reach for the
      // last token it saw — which is dead, and would spend the batches' retry
      // budget on requests that cannot succeed.
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

      await buffer.flush(accessToken: null);

      expect(posts, 0, reason: 'no request under a bearer that is gone');
      expect(buffer.pendingBatches, hasLength(1));
      expect(
        buffer.pendingBatches.single.attempts,
        0,
        reason: 'and no attempt spent on one',
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
        expect(batch.coverage, hasLength(5));
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

    test('a suspended process claims NONE of the time it slept', () async {
      // A flush fires every five minutes while this buffer is running, so a
      // stretch far longer than that is one where the timer was not ticking and
      // nothing was watching. Coverage says the instrument was RUNNING, so none
      // of it may be declared — not even the recent part, which would be the same
      // fabricated zero in a shorter window.
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(bodies),
      );
      buffer.start();
      buffer.record(playback(), accessToken: token);
      clock = clock.add(const Duration(days: 30));
      final wokeAt = clock;
      await buffer.flush(accessToken: token);

      expect(
        _periodsFor(bodies, 'peer'),
        isEmpty,
        reason: 'thirty days nobody watched are not coverage',
      );
      expect(
        (bodies.single['events'] as List),
        hasLength(1),
        reason: 'the playback itself is still a real observation and is sent',
      );

      // And the next seal opens a fresh period after the gap rather than
      // extending across it.
      bodies.clear();
      clock = clock.add(const Duration(minutes: 5));
      await buffer.flush(accessToken: token);
      expect(
        _coverageOf(bodies.single, 'peer')['period_start'],
        wokeAt.toIso8601String(),
      );
    });

    test('one seal can never build a coverage list past its budget', () async {
      // The route caps playbacks and coverage TOGETHER, so the reserve carved out
      // of the event budget has to hold for the biggest coverage list a single
      // seal can produce. Both halves of that arithmetic are pinned here.
      expect(
        DosageAudioBuffer.maxObservedGap,
        lessThan(const Duration(days: 1)),
        reason:
            'a longer gap could cross two midnights and need three segments',
      );
      expect(
        DosageCoverageCategory.values.length *
            DosageAudioBuffer.maxCoverageSegmentsPerSeal,
        DosageAudioBuffer.maxCoverageItemsPerBatch,
        reason: 'adding a coverage category must shrink the event budget',
      );

      // The worst real case: a seal at its longest permitted interval, crossing a
      // midnight, on a batch already full of events.
      clock = DateTime.utc(2026, 1, 1, 23, 50);
      final bodies = <Map<String, dynamic>>[];
      final buffer = DosageAudioBuffer(
        now: () => clock,
        httpClient: _recorder(bodies),
      );
      buffer.start();
      for (var i = 0; i < DosageAudioBuffer.maxEventsPerBatch; i++) {
        buffer.record(playback(), accessToken: token);
      }
      clock = clock.add(DosageAudioBuffer.maxObservedGap);
      await buffer.flush(drainAll: true, accessToken: token);

      expect(bodies, isNotEmpty);
      for (final body in bodies) {
        expect(
          (body['coverage'] as List).length,
          lessThanOrEqualTo(DosageAudioBuffer.maxCoverageItemsPerBatch),
        );
        expect(
          (body['events'] as List).length + (body['coverage'] as List).length,
          lessThanOrEqualTo(DosageAudioBuffer.maxItemsPerBatch),
          reason: 'a body the route would 413 loses that period whole',
        );
      }
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

      expect(buffer.observedFrom, isNull);
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
          (await DosageSignalsRepo.postAudioSignals(
            events: [playback()],
            coverage: const [],
            accessToken: token,
            client: MockClient((_) async => http.Response('', status)),
          )).delivered,
          isTrue,
        );
      }
      for (final status in [400, 401, 404, 413, 422, 500, 503]) {
        expect(
          (await DosageSignalsRepo.postAudioSignals(
            events: [playback()],
            coverage: const [],
            accessToken: token,
            client: MockClient((_) async => http.Response('', status)),
          )).delivered,
          isFalse,
          reason: '$status is undelivered, so the batch is retried',
        );
      }
    });

    test('the written-row count is read off the accepted response', () async {
      // Separate from delivery on purpose: 202 means "do not retry", the count
      // means "the write happened". Only the second licenses an extension.
      Future<DosageAudioPostResult> post(String body) =>
          DosageSignalsRepo.postAudioSignals(
            events: [playback()],
            coverage: const [],
            accessToken: token,
            client: MockClient((_) async => http.Response(body, 202)),
          );

      expect(
        (await post(
          '{"status":"accepted","playbacks":1,"coverage":4}',
        )).coverageWritten,
        4,
      );
      expect(
        (await post(
          '{"status":"accepted","playbacks":0,"coverage":0}',
        )).coverageWritten,
        0,
        reason: 'a write that stored nothing must not license an extension',
      );
      for (final unreadable in ['', 'not json', '[]', '{"coverage":"four"}']) {
        final result = await post(unreadable);
        expect(result.delivered, isTrue);
        expect(
          result.coverageWritten,
          isNull,
          reason: 'unreadable is unknown, never assumed written',
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
        (await DosageSignalsRepo.postAudioSignals(
          events: const [],
          coverage: const [],
          accessToken: token,
          client: client,
        )).delivered,
        isFalse,
      );
      expect(posts, 0);
    });
  });
}

int _seq = 0;

/// A stand-in for the real ingest: records each body and answers the way the
/// route does — 202 with the count of rows it WROTE. The count is what lets the
/// client tell a real write from a 202 over a failed one, so a mock that returned
/// a bare 202 would silently test a contract the server does not offer.
MockClient _recorder(List<Map<String, dynamic>> sink) =>
    MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      sink.add(body);
      return http.Response(
        jsonEncode({
          'status': 'accepted',
          'playbacks': (body['events'] as List).length,
          'coverage': (body['coverage'] as List).length,
        }),
        202,
      );
    });

Map<String, dynamic> _coverageOf(Map<String, dynamic> body, String category) =>
    (body['coverage'] as List).cast<Map<String, dynamic>>().firstWhere(
      (c) => c['category'] == category,
    );

/// One declared period, read back off the wire.
class _Period {
  const _Period(this.start, this.end);
  final DateTime start;
  final DateTime end;

  @override
  String toString() => '${start.toIso8601String()}..${end.toIso8601String()}';
}

/// Every period one category was declared over, across all posted bodies.
List<_Period> _periodsFor(List<Map<String, dynamic>> bodies, String category) =>
    bodies
        .expand((b) => (b['coverage'] as List).cast<Map<String, dynamic>>())
        .where((c) => c['category'] == category)
        .map(
          (c) => _Period(
            DateTime.parse(c['period_start'] as String),
            DateTime.parse(c['period_end'] as String),
          ),
        )
        .toList();

/// Merge overlapping AND ADJACENT periods, exactly as the server's
/// `union_intervals` does — abutting spans are one continuous covered stretch.
/// A result of length one is the proof that the claims tile the observed time
/// with no gap; its bounds are the proof that they do not run past it.
List<_Period> _union(List<_Period> periods) {
  final sorted = [...periods]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <_Period>[];
  for (final period in sorted) {
    if (merged.isEmpty || period.start.isAfter(merged.last.end)) {
      merged.add(period);
      continue;
    }
    if (period.end.isAfter(merged.last.end)) {
      merged[merged.length - 1] = _Period(merged.last.start, period.end);
    }
  }
  return merged;
}
