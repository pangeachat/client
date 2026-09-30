import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
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

/// Nothing here places a call -- both tests render a session that never
/// leaves its opening state, so the service only has to exist. Copied
/// verbatim from `call_mini_tile_test.dart`'s own stubs for the same reason.
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
  final List<PcmChunk> discardedChunks = [];

  @override
  Future<void> deliver(PcmChunk chunk, {Duration? within}) async {}

  @override
  void discarded(PcmChunk chunk) => discardedChunks.add(chunk);

  @override
  Future<bool> close() async => true;
}

/// Task 4 (#8792): beside `callTranscriptSharedNotice`, an unsubscribed local
/// user gets a "Subscribe for Transcription" button that opens subscription
/// settings; a subscribed one sees nothing extra.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUpAll(() async {
    // Both the notice and the gold button draw text through the app's real
    // L10n/theme machinery, which needs the same environment bootstrap
    // `call_mini_tile_test.dart` uses for the same call UI.
    final tempDir = await Directory.systemTemp.createTemp(
      'call_panel_subscribe',
    );
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
    // The generated L10n loads deferred, so an un-preloaded locale leaves
    // `Localizations` rendering an empty placeholder and nothing to assert on.
    await lookupL10n(const Locale('en'));
  });

  late CallSession session;

  Future<CallSession> aSession() async {
    final client = matrix.Client(
      'call-panel-subscribe-test',
      httpClient: matrix.FakeMatrixApi(),
      database: await matrix.MatrixSdkDatabase.init(
        'call-panel-subscribe-test',
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
  // never complete there. Mirrors `call_mini_tile_test.dart`.
  setUp(() async => session = await aSession());
  tearDown(() {
    session.dispose();
    MatrixState.pangeaController = FakePangeaController();
  });

  /// Mounts [CallPanel] behind a REAL [GoRouter] -- the same technique
  /// `overlay_hosted_navigation_test.dart` uses for every other subscription
  /// gate's "opens settings" test -- so the gold button's
  /// `WorkspaceNav.openSettings` / `context.go` has a router to land on
  /// rather than throwing `GoRouterState.of` from a bare `MaterialApp` (#8622).
  Future<GoRouter> pumpCallPanel(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        GoRoute(
          path: '/rooms',
          builder: (context, state) => CallPanel(session: session),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('an unsubscribed local user sees a Subscribe button that opens '
      'subscription settings', (tester) async {
    MatrixState.pangeaController = FakePangeaController(subscribed: false);
    final router = await pumpCallPanel(tester);
    final l10n = L10n.of(tester.element(find.byType(CallPanel)));

    expect(
      find.text(l10n.callTranscriptSubscribeForTranscription),
      findsOneWidget,
    );

    await tester.tap(find.text(l10n.callTranscriptSubscribeForTranscription));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      contains('settingspage:subscription'),
    );
  });

  testWidgets('a subscribed local user sees no Subscribe button', (
    tester,
  ) async {
    MatrixState.pangeaController = FakePangeaController(subscribed: true);
    await pumpCallPanel(tester);
    final l10n = L10n.of(tester.element(find.byType(CallPanel)));

    // Mutation: showing the button unconditionally, without reading
    // `showSubscriptionGatedContent`, would find it here too -> RED.
    expect(
      find.text(l10n.callTranscriptSubscribeForTranscription),
      findsNothing,
    );
  });
}
