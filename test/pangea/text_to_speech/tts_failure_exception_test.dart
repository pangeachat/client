import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// Regression: Sentry CLIENT-E4H, production —
/// `Exception: Error getting text to speech: Instance of 'minified:xs'` (#8375).
///
/// `requestTextToSpeech` wrapped the repo's failure in a bare
/// `Exception("Error getting text to speech: $error")`. That did two kinds of
/// damage, both pinned below:
///
///  - String-interpolating an exception with no `toString()` renders it as
///    `Instance of '<minified class>'`, so every cause collapsed into one
///    undiagnosable Sentry title — the same defect `PangeaHttpException` exists
///    to prevent for raw `Response` throws.
///  - Erasing the type stopped `UnsubscribedException` being recognizable as
///    control flow. Both `BaseRepo._fetch` and `AsyncLoader.load` deliberately
///    skip reporting it; the wrapper defeated them, so a free user tapping
///    message audio filed a Sentry error.
///
/// Design: client/.github/instructions/repos-and-error-handling.instructions.md
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `Environment.choreoApi` consults a GetStorage-backed config override before
  // dotenv, so path_provider has to answer before the URL can be built.
  final tempDir = Directory.systemTemp.createTempSync('tts_failure_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  setUpAll(() async {
    // The fetch must actually reach the network so the MockClient answers it,
    // which is what makes `Requests` throw the real typed failure.
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'test-token',
    );
    dotenv.testLoad(mergeWith: {'CHOREO_API': 'https://choreo.test'});
    await GetStorage.init('env_override');
  });

  group('UnsubscribedException renders legibly', () {
    test('names itself instead of falling back to Object.toString', () {
      // In a release web build a class with no `toString()` renders as
      // `Instance of 'minified:xs'` — the exact title on CLIENT-E4H.
      expect(UnsubscribedException().toString(), 'UnsubscribedException');
    });

    test('stays legible when interpolated into a message', () {
      expect('${UnsubscribedException()}', isNot(contains('Instance of')));
    });
  });

  group('requestTextToSpeech surfaces the real cause', () {
    late Client client;
    late Room room;
    late Timeline timeline;

    setUp(() async {
      client = await getTestClient();
      room = Room(id: '!tts:fakeServer.notExisting', client: client);
      timeline = await room.getTimeline();
    });

    tearDown(() async {
      timeline.cancelSubscriptions();
      await client.dispose();
    });

    /// An audio message, so `messageDisplayLangCode` resolves from the (absent)
    /// transcript rather than the user's immersion-mode setting.
    PangeaMessageEvent messageWithBody(String body) => PangeaMessageEvent(
      event: Event(
        type: EventTypes.Message,
        eventId: '\$tts-$body:fakeServer.notExisting',
        senderId: client.userID!,
        originServerTs: DateTime.now(),
        content: {'msgtype': 'm.audio', 'body': body},
        room: room,
      ),
      timeline: timeline,
      ownMessage: true,
    );

    Future<Object?> errorFromTts(
      String body,
      http.Response Function(http.Request) respond,
    ) async {
      Object? thrown;
      await http.runWithClient(() async {
        try {
          await messageWithBody(body).requestTextToSpeech('es', null);
        } catch (e) {
          thrown = e;
        }
      }, () => MockClient((request) async => respond(request)));
      return thrown;
    }

    test('rethrows UnsubscribedException with its own type', () async {
      // Exactly what the backend sends a free user: backend TTS is
      // entitlement-gated, so `Requests` turns this into the control-flow
      // exception that is never meant to be reported.
      final thrown = await errorFromTts(
        'unsubscribed',
        (_) => http.Response('{"detail": "No active subscription found"}', 401),
      );

      // Teeth: the old wrapper made this an anonymous `Exception`, so every
      // `is UnsubscribedException` suppression downstream missed it.
      expect(thrown, isA<UnsubscribedException>());
      expect(thrown.toString(), isNot(contains('Instance of')));
    });

    test('rethrows PangeaHttpException with a diagnosable toString', () async {
      final thrown = await errorFromTts(
        'server-error',
        (request) => http.Response(
          '{"detail": "voice synthesis failed"}',
          502,
          request: request,
        ),
      );

      expect(thrown, isA<PangeaHttpException>());
      // The real cause — status, method, normalized path, capped detail —
      // reaches the Sentry title instead of a wrapper string.
      expect(
        thrown.toString(),
        'PangeaHttpException: 502 POST /choreo/text_to_speech'
        ' — voice synthesis failed',
      );
      // Teeth: the old throw prefixed every cause with this, collapsing them
      // all into one issue.
      expect(
        thrown.toString(),
        isNot(contains('Error getting text to speech')),
      );
    });
  });
}
