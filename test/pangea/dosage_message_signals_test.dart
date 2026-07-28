import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/dosage/dosage_engagement_tracker.dart';
import 'package:fluffychat/features/dosage/dosage_message_signals.dart';

/// Unit tests for the shared learner-message emitter ([DosageMessageSignals]) —
/// the single place every learner-text send path emits the envelope + an
/// engagement tick. Driven with an injected clock, HTTP client, and tracker so
/// no Matrix boot is needed.

/// A tracker whose synchronous [recordActivity] throws, to prove the emit's
/// best-effort boundary swallows it and never lets it escape into the send flow.
class _ThrowingTracker extends DosageEngagementTracker {
  @override
  void recordActivity({
    required String userId,
    required String deviceId,
    required String? accessToken,
  }) => throw StateError('boom in the engagement tick');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bffUrl = 'https://bff.test.example';
  const token = 'syt_token';
  const roomId = '!room:example.org';
  const msgId = '\$msg:example.org';
  const deviceId = 'DEVICE-A';
  const userId = '@user:example.org';
  final base = DateTime.utc(2026, 1, 1, 12);

  late List<http.Request> requests;
  late http.Client mock;
  late DateTime clock;

  DosageEngagementTracker buildTracker() =>
      DosageEngagementTracker(now: () => clock, httpClient: mock);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  List<http.Request> reqsFor(String path) =>
      requests.where((r) => r.url.path.contains(path)).toList();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('dosage_msgsig_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() {
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': bffUrl,
      },
    );
    requests = [];
    mock = MockClient((req) async {
      requests.add(req);
      return http.Response('', 202);
    });
    clock = base;
    // Isolate the per-account tracker registry between tests.
    DosageEngagementTracker.debugResetAccounts();
  });

  test(
    'emits the envelope AND opens an engagement span for a valid send',
    () async {
      final tracker = buildTracker();
      DosageMessageSignals.emitForSentMessage(
        roomId: roomId,
        userId: userId,
        deviceId: deviceId,
        accessToken: token,
        msgEventId: msgId,
        body: 'hola mundo',
        tokenCount: 2,
        langCode: 'es',
        ts: base,
        client: mock,
        tracker: tracker,
      );
      await settle();

      final envelopes = reqsFor('/dosage/message-events');
      expect(envelopes, hasLength(1));
      final event =
          (jsonDecode(envelopes.single.body)['events'] as List).single
              as Map<String, dynamic>;
      expect(event['msg_id'], msgId);
      expect(event['token_count'], 2);
      expect(event['lang_code'], 'es');

      // The engagement span opened; flushing it posts a span.
      clock = base.add(const Duration(minutes: 2));
      tracker.flushOpenSpan();
      await settle();
      expect(reqsFor('/dosage/engagement-spans'), hasLength(1));
    },
  );

  test(
    'skips everything on a null/blank event id (send did not land)',
    () async {
      final tracker = buildTracker();
      for (final id in [null, '', '   ']) {
        DosageMessageSignals.emitForSentMessage(
          roomId: roomId,
          userId: userId,
          deviceId: deviceId,
          accessToken: token,
          msgEventId: id,
          body: 'hola',
          client: mock,
          tracker: tracker,
        );
      }
      // A blank id resolves to no envelope; the tracker never opened a span.
      clock = base.add(const Duration(minutes: 5));
      tracker.flushOpenSpan();
      await settle();
      expect(requests, isEmpty);
    },
  );

  test(
    'posts the envelope but opens NO span when the device id is empty',
    () async {
      final tracker = buildTracker();
      DosageMessageSignals.emitForSentMessage(
        roomId: roomId,
        userId: userId,
        deviceId: '',
        accessToken: token,
        msgEventId: msgId,
        body: 'hola',
        client: mock,
        tracker: tracker,
      );
      clock = base.add(const Duration(minutes: 5));
      tracker.flushOpenSpan();
      await settle();

      expect(reqsFor('/dosage/message-events'), hasLength(1));
      expect(reqsFor('/dosage/engagement-spans'), isEmpty);
    },
  );

  test(
    'skips the envelope and engagement tick for an edit (editEventId set)',
    () async {
      final tracker = buildTracker();
      DosageMessageSignals.emitForSentMessage(
        roomId: roomId,
        userId: userId,
        deviceId: deviceId,
        accessToken: token,
        // A Matrix edit is a NEW event id, but the same learner turn.
        msgEventId: '\$edit-replacement:example.org',
        body: 'hola mundo (edited)',
        tokenCount: 3,
        langCode: 'es',
        editEventId: '\$original:example.org',
        ts: base,
        client: mock,
        tracker: tracker,
      );
      // No new envelope, and the tracker never opened a span — one turn stays
      // one envelope + one engagement tick.
      clock = base.add(const Duration(minutes: 5));
      tracker.flushOpenSpan();
      await settle();
      expect(requests, isEmpty);
    },
  );

  test('is a no-op when the dosage flag is off', () async {
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'false',
        'TEACHER_BFF_API': bffUrl,
      },
    );
    final tracker = buildTracker();
    DosageMessageSignals.emitForSentMessage(
      roomId: roomId,
      userId: userId,
      deviceId: deviceId,
      accessToken: token,
      msgEventId: msgId,
      body: 'hola',
      client: mock,
      tracker: tracker,
    );
    clock = base.add(const Duration(minutes: 5));
    tracker.flushOpenSpan();
    await settle();
    expect(requests, isEmpty);
  });

  test('a throwing engagement tick never escapes the emit boundary', () async {
    // A tracker whose synchronous recordActivity throws must NOT surface into
    // the send flow — the whole emit is inside a best-effort guard.
    expect(
      () => DosageMessageSignals.emitForSentMessage(
        roomId: roomId,
        userId: userId,
        deviceId: deviceId,
        accessToken: token,
        msgEventId: msgId,
        body: 'hola',
        client: mock,
        tracker: _ThrowingTracker(),
      ),
      returnsNormally,
      reason:
          'a tracker/serialization throw must be swallowed, never thrown '
          'into the caller (the send/save flow)',
    );
    await settle();
    // The envelope POST still fired (it runs before the tracker tick).
    expect(reqsFor('/dosage/message-events'), hasLength(1));
  });

  group('isResendableLearnerText (resend emit gate)', () {
    test('a text resend is a learner turn', () {
      expect(
        DosageMessageSignals.isResendableLearnerText(MessageTypes.Text),
        isTrue,
      );
    });

    test('a file/image/audio/video resend is not (no learner text)', () {
      for (final type in [
        MessageTypes.Image,
        MessageTypes.File,
        MessageTypes.Audio,
        MessageTypes.Video,
      ]) {
        expect(
          DosageMessageSignals.isResendableLearnerText(type),
          isFalse,
          reason: '$type carries no learner text',
        );
      }
    });
  });

  group('learnerText (reply-RELATION strip, not body shape)', () {
    Map<String, dynamic> reply(String body) => {
      'msgtype': 'm.text',
      'body': body,
      'm.relates_to': {
        'm.in_reply_to': {'event_id': '\$orig'},
      },
    };

    test('strips the quoted fallback when the message IS a reply', () {
      expect(
        DosageMessageSignals.learnerText(
          reply('> <@bob:example.org> the original\n\nmy actual reply'),
        ),
        'my actual reply',
      );
    });

    test('strips a multi-line quoted fallback (reply)', () {
      expect(
        DosageMessageSignals.learnerText(
          reply('> <@bob:example.org> line one\n> line two\n\nreply'),
        ),
        'reply',
      );
    });

    test(
      'does NOT strip ordinary text that merely LOOKS like a quote (no reply '
      'relation)',
      () {
        // Same body shape as a reply fallback, but no m.in_reply_to — this is
        // the learner's own text and must be counted in full.
        const body = '> <@bob:example.org> quoting a friend\n\nmy point';
        expect(
          DosageMessageSignals.learnerText({'msgtype': 'm.text', 'body': body}),
          body,
          reason: 'strip keys on the reply relation, not the body shape',
        );
      },
    );

    test('leaves a plain message unchanged', () {
      expect(
        DosageMessageSignals.learnerText({
          'msgtype': 'm.text',
          'body': 'just a normal message',
        }),
        'just a normal message',
      );
    });
  });
}
