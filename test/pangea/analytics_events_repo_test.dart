import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_events_repo.dart';

/// Unit tests for the best-effort analytics dual-write ([AnalyticsEventsRepo]).
///
/// The repo is deliberately independent of the Matrix client and the app
/// god-object: it takes the room id, the resolved event id, the raw uses, and
/// the access token as plain arguments, and its HTTP client is injectable. So
/// these tests need no Matrix boot — only a [MockClient] and a controlled
/// [Environment] (via `dotenv.testLoad`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bffUrl = 'https://bff.test.example';
  const token = 'syt_student_token';
  const roomId = '!analytics:example.org';
  const eventId = '\$realEventId:example.org';

  OneConstructUse buildUse({
    required String lemma,
    ConstructUseTypeEnum useType = ConstructUseTypeEnum.wa,
  }) {
    return OneConstructUse(
      useType: useType,
      lemma: lemma,
      form: lemma,
      category: 'noun',
      constructType: ConstructTypeEnum.vocab,
      xp: 5,
      metadata: ConstructUseMetaData(
        roomId: '!chat:example.org',
        eventId: '\$msg:example.org',
        timeStamp: DateTime.utc(2026, 1, 1),
      ),
    );
  }

  setUpAll(() async {
    // Environment.appConfigOverride constructs a GetStorage('env_override') box,
    // which needs path_provider. Stub the platform channel to a temp dir so the
    // box initializes silently (its read then returns null and the flag falls
    // back to dotenv). Without this stub GetStorage's async init throws.
    final tempDir = await Directory.systemTemp.createTemp(
      'analytics_repo_test',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() {
    // Enabled + configured by default; individual tests override as needed.
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'TEACHER_BFF_API': bffUrl,
      },
    );
  });

  test(
    'posts the exact contract body to the BFF on a successful write',
    () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response('{"status":"accepted"}', 202);
      });

      final uses = [buildUse(lemma: 'hola'), buildUse(lemma: 'gato')];

      await AnalyticsEventsRepo.postConstructUses(
        analyticsRoomId: roomId,
        matrixEventId: eventId,
        uses: uses,
        accessToken: token,
        client: mock,
      );

      expect(captured, isNotNull, reason: 'the POST must fire when enabled');
      expect(captured!.method, 'POST');
      expect(captured!.url.toString(), '$bffUrl/api/internal/analytics-events');
      expect(captured!.headers['Authorization'], 'Bearer $token');
      expect(captured!.headers['Content-Type'], contains('application/json'));

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      // Top-level shape is EXACTLY the contract: analytics_room_id + events.
      // No cefr/gender/mock injection (that would 422 the extra="forbid" server).
      expect(body.keys.toSet(), {'analytics_room_id', 'events'});
      expect(body['analytics_room_id'], roomId);

      final events = body['events'] as List;
      expect(events, hasLength(1));
      final event = events.single as Map<String, dynamic>;
      expect(event['matrix_event_id'], eventId);

      // uses[] are the verbatim OneConstructUse.toJson dicts, in order — so the
      // server's 0-based use_index matches the client's array position.
      final sentUses = event['uses'] as List;
      expect(sentUses, hasLength(2));
      expect(sentUses[0], equals(uses[0].toJson()));
      expect(sentUses[1], equals(uses[1].toJson()));
      expect((sentUses[0] as Map)['lemma'], 'hola');
      expect((sentUses[1] as Map)['lemma'], 'gato');
    },
  );

  test('sends the REAL event id, never a blank/placeholder', () async {
    // A blank id is a pre-send/optimistic post the server would reject (422);
    // the repo must skip it rather than post it.
    var fired = false;
    final mock = MockClient((req) async {
      fired = true;
      return http.Response('', 202);
    });

    await AnalyticsEventsRepo.postConstructUses(
      analyticsRoomId: roomId,
      matrixEventId: '   ',
      uses: [buildUse(lemma: 'hola')],
      accessToken: token,
      client: mock,
    );
    expect(fired, isFalse, reason: 'a blank id must not be posted');

    // And with a real id, the id on the wire is exactly what was passed in.
    http.Request? captured;
    final mock2 = MockClient((req) async {
      captured = req;
      return http.Response('', 202);
    });
    await AnalyticsEventsRepo.postConstructUses(
      analyticsRoomId: roomId,
      matrixEventId: eventId,
      uses: [buildUse(lemma: 'hola')],
      accessToken: token,
      client: mock2,
    );
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect((body['events'] as List).single['matrix_event_id'], eventId);
  });

  test('a POST failure never throws and never blocks the caller', () async {
    final throwingClient = MockClient((req) async {
      throw http.ClientException('network down');
    });

    // Must complete normally (no rethrow) despite the transport blowing up.
    await expectLater(
      AnalyticsEventsRepo.postConstructUses(
        analyticsRoomId: roomId,
        matrixEventId: eventId,
        uses: [buildUse(lemma: 'hola')],
        accessToken: token,
        client: throwingClient,
      ),
      completes,
    );

    // A non-2xx response is likewise swallowed (best-effort, server always 202).
    final errorClient = MockClient((req) async => http.Response('boom', 500));
    await expectLater(
      AnalyticsEventsRepo.postConstructUses(
        analyticsRoomId: roomId,
        matrixEventId: eventId,
        uses: [buildUse(lemma: 'hola')],
        accessToken: token,
        client: errorClient,
      ),
      completes,
    );
  });

  test('is a no-op (no POST) when the feature flag is off', () async {
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'false',
        'TEACHER_BFF_API': bffUrl,
      },
    );
    expect(AnalyticsEventsRepo.isEnabled, isFalse);

    var fired = false;
    final mock = MockClient((req) async {
      fired = true;
      return http.Response('', 202);
    });
    await AnalyticsEventsRepo.postConstructUses(
      analyticsRoomId: roomId,
      matrixEventId: eventId,
      uses: [buildUse(lemma: 'hola')],
      accessToken: token,
      client: mock,
    );
    expect(fired, isFalse);
  });

  test('is a no-op (no POST) when the BFF URL is not configured', () async {
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'TEACHER_BFF_API': '',
      },
    );
    expect(AnalyticsEventsRepo.isEnabled, isFalse);

    var fired = false;
    final mock = MockClient((req) async {
      fired = true;
      return http.Response('', 202);
    });
    await AnalyticsEventsRepo.postConstructUses(
      analyticsRoomId: roomId,
      matrixEventId: eventId,
      uses: [buildUse(lemma: 'hola')],
      accessToken: token,
      client: mock,
    );
    expect(fired, isFalse);
  });

  test('skips when there is no access token or no uses', () async {
    var fired = false;
    final mock = MockClient((req) async {
      fired = true;
      return http.Response('', 202);
    });

    await AnalyticsEventsRepo.postConstructUses(
      analyticsRoomId: roomId,
      matrixEventId: eventId,
      uses: [buildUse(lemma: 'hola')],
      accessToken: null,
      client: mock,
    );
    expect(fired, isFalse, reason: 'no token => skip');

    await AnalyticsEventsRepo.postConstructUses(
      analyticsRoomId: roomId,
      matrixEventId: eventId,
      uses: const [],
      accessToken: token,
      client: mock,
    );
    expect(fired, isFalse, reason: 'no uses => skip');
  });
}
