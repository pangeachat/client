import 'dart:io';
import 'dart:ui' as ui show SemanticsHitTestBehavior;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_panel.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_session.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

/// Nothing here places a call — both views are rendered from a session that
/// never leaves its opening state, so the service only has to exist.
class _StubCalls extends CallService {
  _StubCalls(super.client);
}

class _StubMedia extends CallMedia {
  @override
  Future<void> connect(CallToken grant, {required bool video}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}
}

class _NullSink implements CallAudioSink {
  @override
  Future<void> deliver(PcmChunk chunk, {Duration? within}) async {}

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUpAll(() async {
    // Both views draw an Avatar, which reads BotName.byEnvironment.
    final tempDir = await Directory.systemTemp.createTemp('call_mini_tile');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': 'pangeabot',
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
    MatrixState.pangeaController = FakePangeaController();
    // The generated L10n loads deferred, so an un-preloaded locale leaves
    // `Localizations` rendering an empty placeholder and nothing to assert on.
    await lookupL10n(const Locale('en'));
  });

  late CallSession session;

  Future<CallSession> aSession() async {
    final client = matrix.Client(
      'call-mini-tile-test',
      httpClient: matrix.FakeMatrixApi(),
      database: await matrix.MatrixSdkDatabase.init(
        'call-mini-tile-test',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    await client.login(
      matrix.LoginType.mLoginPassword,
      token: 'abcd',
      identifier: matrix.AuthenticationUserIdentifier(
        user: '@test:fakeServer.notExisting',
      ),
      deviceId: 'GHTYAJCE',
    );
    await client.abortSync();
    return CallSession.start(
      room: matrix.Room(id: '!r:server', client: client),
      video: false,
      callService: _StubCalls(client),
      transcribe: (request) async =>
          SpeechToTextResponseModel(results: const []),
      userL1: 'en',
      userL2: 'es',
      analytics: (eventId, uses, language) async {},
      onReleased: (_) {},
      mediaOverride: _StubMedia(),
      captureOverride: CallCaptureService(sink: _NullSink()),
    );
  }

  // Built in setUp, never inside a test body: `testWidgets` runs its body in a
  // fake-async zone, and the database and login here are real I/O that would
  // never complete there.
  setUp(() async => session = await aSession());
  tearDown(() => session.dispose());

  Future<void> pumpCallUi(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The call floats over whatever the learner is looking at, and on web with
  // the semantics tree on (staging forces it via ENABLE_SEMANTICS) the browser
  // dispatches a click from the `flt-semantics` element under the cursor
  // rather than from Flutter's hit test. Without an opaque node of its own the
  // bar is not a container boundary: the page's nodes end up nested INSIDE the
  // bar's and therefore on top of it, so a tap on the bar pressed the button
  // it was covering and a tap anywhere else on the page expanded the call
  // (#8681). A widget test cannot exercise the DOM, so these lock the one
  // property the fix rests on.
  testWidgets('the minimized bar is opaque to hit testing', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCallUi(tester, CallMiniTile(session: session, onOpen: () {}));

    expect(
      tester.getSemantics(find.byType(CallMiniTile)).hitTestBehavior,
      ui.SemanticsHitTestBehavior.opaque,
      reason: 'without this the bar can be clicked through on web',
    );
    // The bar absorbing the page's clicks must not cost it its own controls:
    // they are children of the opaque node, and children still get theirs.
    expect(
      find.bySemanticsLabel(
        L10n.of(tester.element(find.byType(CallMiniTile))).callHangUp,
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  // The expanded panel covers the whole app in fullscreen and the chat pane
  // otherwise, and its dark Material publishes no node of its own -- so it had
  // the same hole as the bar, one tap away from it.
  testWidgets('the expanded panel is opaque to hit testing', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCallUi(tester, CallPanel(session: session));

    expect(
      tester.getSemantics(find.byType(CallPanel)).hitTestBehavior,
      ui.SemanticsHitTestBehavior.opaque,
      reason: 'without this the call screen can be clicked through on web',
    );
    handle.dispose();
  });
}
