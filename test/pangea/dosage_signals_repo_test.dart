import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/dosage/dosage_engagement_span.dart';
import 'package:fluffychat/features/dosage/dosage_message_event.dart';
import 'package:fluffychat/features/dosage/dosage_session_outcome.dart';
import 'package:fluffychat/features/dosage/dosage_signals_repo.dart';

/// Unit tests for the best-effort dosage signals ([DosageSignalsRepo]), mirroring
/// the analytics dual-write suite: the repo takes plain arguments and an
/// injectable HTTP client, so no Matrix boot is needed — only a [MockClient] and
/// a controlled [Environment] (via `dotenv.testLoad`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bffUrl = 'https://bff.test.example';
  const token = 'syt_student_token';
  const roomId = '!room:example.org';
  const msgId = '\$msg:example.org';

  DosageMessageEvent messageEvent({String? langCode = 'es'}) =>
      DosageMessageEvent.fromSentMessage(
        roomId: roomId,
        msgId: msgId,
        ts: DateTime.utc(2026, 1, 1, 12),
        body: 'hola mundo',
        tokenCount: 2,
        langCode: langCode,
      );

  DosageEngagementSpan engagementSpan() => DosageEngagementSpan(
    deviceId: 'DEVICE1',
    spanId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    spanStart: DateTime.utc(2026, 1, 1, 12),
    spanEnd: DateTime.utc(2026, 1, 1, 12, 5),
    platform: 'web',
  );

  DosageSessionOutcome sessionOutcome() => DosageSessionOutcome(
    sessionRoomId: '!session:example.org',
    activityId: 'activity-123',
    sourceCourseId: 'course-9',
    loRefs: const ['lo-1'],
    starsByGoalSlug: const {'greet-politely': 1},
    completedAt: DateTime.utc(2026, 1, 1, 12, 30),
  );

  setUpAll(() async {
    // Environment.appConfigOverride constructs a GetStorage('env_override') box,
    // which needs path_provider. Stub the platform channel to a temp dir so the
    // box initializes silently (its read then returns null and the flags fall
    // back to dotenv).
    final tempDir = await Directory.systemTemp.createTemp('dosage_repo_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() {
    // All three gates on by default; individual tests override as needed.
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': bffUrl,
      },
    );
  });

  test('isEnabled requires ALL THREE gates (triple-gated)', () {
    expect(DosageSignalsRepo.isEnabled, isTrue);

    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'false',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': bffUrl,
      },
    );
    expect(DosageSignalsRepo.isEnabled, isFalse, reason: 'dual-write gate off');

    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'false',
        'TEACHER_BFF_API': bffUrl,
      },
    );
    expect(DosageSignalsRepo.isEnabled, isFalse, reason: 'dosage gate off');

    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': '',
      },
    );
    expect(DosageSignalsRepo.isEnabled, isFalse, reason: 'no BFF url');
  });

  test(
    'message-events: posts the exact contract body (no sender/lang_source)',
    () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response('', 202);
      });

      await DosageSignalsRepo.postMessageEvents(
        events: [messageEvent()],
        accessToken: token,
        client: mock,
      );

      expect(captured, isNotNull);
      expect(captured!.method, 'POST');
      expect(
        captured!.url.toString(),
        '$bffUrl/api/internal/dosage/message-events',
      );
      expect(captured!.headers['Authorization'], 'Bearer $token');
      expect(captured!.headers['Content-Type'], contains('application/json'));

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body.keys.toSet(), {'events'});
      final event = (body['events'] as List).single as Map<String, dynamic>;
      // EXACTLY the six contract keys — no `sender`, no `lang_source`.
      expect(event.keys.toSet(), {
        'room_id',
        'msg_id',
        'ts',
        'token_count',
        'char_count',
        'lang_code',
      });
      expect(event.containsKey('lang_source'), isFalse);
      expect(event.containsKey('sender'), isFalse);
      expect(event['room_id'], roomId);
      expect(event['msg_id'], msgId);
      expect(event['token_count'], 2);
      expect(event['char_count'], 'hola mundo'.length);
      expect(event['lang_code'], 'es');
      expect(event['ts'], endsWith('Z'), reason: 'timestamp must be UTC-aware');
    },
  );

  test('engagement-spans: posts the exact contract body (no sender)', () async {
    http.Request? captured;
    final mock = MockClient((req) async {
      captured = req;
      return http.Response('', 202);
    });

    await DosageSignalsRepo.postEngagementSpans(
      spans: [engagementSpan()],
      accessToken: token,
      client: mock,
    );

    expect(
      captured!.url.toString(),
      '$bffUrl/api/internal/dosage/engagement-spans',
    );
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body.keys.toSet(), {'spans'});
    final span = (body['spans'] as List).single as Map<String, dynamic>;
    expect(span.keys.toSet(), {
      'device_id',
      'span_id',
      'span_start',
      'span_end',
      'platform',
    });
    expect(span.containsKey('sender'), isFalse);
    expect(span['device_id'], 'DEVICE1');
    expect(span['platform'], 'web');
    expect(span['span_start'], endsWith('Z'));
    expect(span['span_end'], endsWith('Z'));
  });

  test('session-outcomes: posts the exact contract body (no sender)', () async {
    http.Request? captured;
    final mock = MockClient((req) async {
      captured = req;
      return http.Response('', 202);
    });

    await DosageSignalsRepo.postSessionOutcomes(
      outcomes: [sessionOutcome()],
      accessToken: token,
      client: mock,
    );

    expect(
      captured!.url.toString(),
      '$bffUrl/api/internal/dosage/session-outcomes',
    );
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body.keys.toSet(), {'outcomes'});
    final outcome = (body['outcomes'] as List).single as Map<String, dynamic>;
    expect(outcome.keys.toSet(), {
      'session_room_id',
      'activity_id',
      'source_course_id',
      'lo_refs',
      'stars_by_goal_slug',
      'completed_at',
    });
    expect(outcome.containsKey('sender'), isFalse);
    expect(outcome['activity_id'], 'activity-123');
    expect(outcome['lo_refs'], ['lo-1']);
    expect(outcome['stars_by_goal_slug'], {'greet-politely': 1});
    expect(outcome['completed_at'], endsWith('Z'));
  });

  test('all three are no-ops when any gate is off', () async {
    for (final env in [
      {'ANALYTICS_DUAL_WRITE_ENABLED': 'false'},
      {'DOSAGE_SIGNALS_ENABLED': 'false'},
      {'TEACHER_BFF_API': ''},
    ]) {
      dotenv.testLoad(
        mergeWith: {
          'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
          'DOSAGE_SIGNALS_ENABLED': 'true',
          'TEACHER_BFF_API': bffUrl,
          ...env,
        },
      );

      var fired = false;
      final mock = MockClient((req) async {
        fired = true;
        return http.Response('', 202);
      });
      await DosageSignalsRepo.postMessageEvents(
        events: [messageEvent()],
        accessToken: token,
        client: mock,
      );
      await DosageSignalsRepo.postEngagementSpans(
        spans: [engagementSpan()],
        accessToken: token,
        client: mock,
      );
      await DosageSignalsRepo.postSessionOutcomes(
        outcomes: [sessionOutcome()],
        accessToken: token,
        client: mock,
      );
      expect(fired, isFalse, reason: 'gate $env should suppress every POST');
    }
  });

  test('abandons a POST that never responds at the request timeout '
      '(no indefinite hang)', () async {
    DosageSignalsRepo.requestTimeout = const Duration(milliseconds: 50);
    addTearDown(
      () => DosageSignalsRepo.requestTimeout = const Duration(seconds: 10),
    );
    // A client whose response future never completes.
    final hang = MockClient((req) => Completer<http.Response>().future);

    // The internal timeout resolves the future; the outer guard fails the
    // test (rather than hanging it) if the timeout is missing.
    await DosageSignalsRepo.postMessageEvents(
      events: [messageEvent()],
      accessToken: token,
      client: hang,
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('postMessageEvents hung past the request timeout'),
    );
  });

  test('dispose() closes and releases the shared client (lazy recreate)', () {
    final first = DosageSignalsRepo.debugDefaultClient;
    expect(
      identical(first, DosageSignalsRepo.debugDefaultClient),
      isTrue,
      reason: 'the shared client is reused across posts',
    );

    DosageSignalsRepo.dispose();

    expect(
      identical(first, DosageSignalsRepo.debugDefaultClient),
      isFalse,
      reason:
          'dispose released the shared client; the next access recreates it',
    );
    DosageSignalsRepo.dispose();
  });

  test('never throws and never blocks on a failing/erroring client', () async {
    final throwing = MockClient((req) async {
      throw http.ClientException('network down');
    });
    final error500 = MockClient((req) async => http.Response('boom', 500));

    for (final client in [throwing, error500]) {
      await expectLater(
        DosageSignalsRepo.postMessageEvents(
          events: [messageEvent()],
          accessToken: token,
          client: client,
        ),
        completes,
      );
      await expectLater(
        DosageSignalsRepo.postEngagementSpans(
          spans: [engagementSpan()],
          accessToken: token,
          client: client,
        ),
        completes,
      );
      await expectLater(
        DosageSignalsRepo.postSessionOutcomes(
          outcomes: [sessionOutcome()],
          accessToken: token,
          client: client,
        ),
        completes,
      );
    }
  });

  test('skips on empty token, empty list, or missing required ids', () async {
    var fired = false;
    final mock = MockClient((req) async {
      fired = true;
      return http.Response('', 202);
    });

    // No token.
    await DosageSignalsRepo.postMessageEvents(
      events: [messageEvent()],
      accessToken: null,
      client: mock,
    );
    // Empty lists.
    await DosageSignalsRepo.postMessageEvents(
      events: const [],
      accessToken: token,
      client: mock,
    );
    // Missing required ids: empty room/msg id, empty device id, zero-length
    // span, missing session/activity id.
    await DosageSignalsRepo.postMessageEvents(
      events: [
        DosageMessageEvent.fromSentMessage(
          roomId: '',
          msgId: '',
          ts: DateTime.utc(2026),
          body: 'x',
          tokenCount: 1,
        ),
      ],
      accessToken: token,
      client: mock,
    );
    await DosageSignalsRepo.postEngagementSpans(
      spans: [
        DosageEngagementSpan(
          deviceId: '',
          spanId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          spanStart: DateTime.utc(2026, 1, 1, 12),
          spanEnd: DateTime.utc(2026, 1, 1, 12, 5),
          platform: 'web',
        ),
        // span_end == span_start violates the server CHECK.
        DosageEngagementSpan(
          deviceId: 'D',
          spanId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          spanStart: DateTime.utc(2026, 1, 1, 12),
          spanEnd: DateTime.utc(2026, 1, 1, 12),
          platform: 'web',
        ),
      ],
      accessToken: token,
      client: mock,
    );
    await DosageSignalsRepo.postSessionOutcomes(
      outcomes: [
        DosageSessionOutcome(
          sessionRoomId: '',
          activityId: '',
          sourceCourseId: null,
          loRefs: const [],
          starsByGoalSlug: const {},
          completedAt: DateTime.utc(2026),
        ),
      ],
      accessToken: token,
      client: mock,
    );

    expect(fired, isFalse);
  });
}
