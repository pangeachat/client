import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' show Response, runWithClient;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/subscription/widgets/unlock_button.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/phonetic_transcription_widget.dart';
import 'package:fluffychat/routes/chat/html_message.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/message_unsubscribed_card.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// Controls that navigate from inside an `OverlayEntry`.
///
/// The word card is shown as one — over a vocab chip on the activity surfaces,
/// over a message in chat — and so is the message toolbar, which renders its
/// own copy of the selected message. An entry sits BESIDE the route's page in
/// the Navigator's overlay, not under it, so `ModalRoute.of` finds nothing
/// there and `GoRouterState.of` throws. Every navigation these surfaces offer
/// used to die on that throw inside an async tap handler, which is why the
/// controls did nothing at all rather than reporting an error (#8622, #8629).
///
/// Read the current URI from the router instead. These tests pin that: they
/// mount each control in a real `OverlayEntry` and assert it navigated.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const choreoApi = 'https://api.test.pangea.chat';

  // Built in `setUp`, not in the test body: logging the SDK client in runs on
  // real timers, which a `testWidgets` fake clock never advances.
  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    // The transcription repo caches to disk and reads the env for its host, so
    // the fetch under test has to be able to get as far as the network.
    final tempDir = await Directory.systemTemp.createTemp('overlay_nav');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    // The word card's audio affordances tear down through the TTS plugin. The
    // `get*` queries must answer with a list — the plugin's dynamic returns are
    // cast, and a cast failure breaks into the debugger and hangs the run.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (methodCall) async => methodCall.method.startsWith('get') ? [] : 1,
        );
    await GetStorage.init('env_override');
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
  });

  tearDown(() async => client.dispose());

  setUp(() async {
    client = await getTestClient();
    dotenv.testLoad(
      mergeWith: {
        'CHOREO_API': choreoApi,
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
  });

  /// Mounts [card] in an `OverlayEntry` over a route, the way the real word
  /// card is shown, and returns the router so a test can read the URL back.
  ///
  /// [wrap] puts an ancestor above the router — a `Matrix` for the controls
  /// that read the client back out of the tree.
  ///
  /// [settle] must be false for a card that never stops animating: the
  /// transcription strip shimmers while it loads, so `pumpAndSettle` would time
  /// out rather than reach the card.
  Future<GoRouter> pumpOverOverlay(
    WidgetTester tester,
    Widget card, {
    Widget Function(Widget app)? wrap,
    bool settle = true,
  }) async {
    final router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        GoRoute(
          path: '/rooms',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (inner) => TextButton(
                onPressed: () => Overlay.of(inner).insert(
                  OverlayEntry(
                    builder: (_) =>
                        Align(alignment: Alignment.topLeft, child: card),
                  ),
                ),
                child: const Text('open card'),
              ),
            ),
          ),
        ),
      ],
    );

    final app = MaterialApp.router(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      routerConfig: router,
    );

    await tester.pumpWidget(wrap == null ? app : wrap(app));
    // L10n's delegate resolves from a deferred library, so nothing is in the
    // tree until localizations finish loading.
    settle
        ? await tester.pumpAndSettle()
        : await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('open card'));
    settle
        ? await tester.pumpAndSettle()
        : await tester.pump(const Duration(milliseconds: 100));
    return router;
  }

  testWidgets('the unlock gate opens subscription settings', (tester) async {
    final router = await pumpOverOverlay(
      tester,
      MessageUnsubscribedCard(
        token: PangeaTokenText.fromString('Deutsch'),
        onClose: () {},
      ),
    );

    await tester.tap(find.byType(UnlockButton));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      contains('settingspage:subscription'),
    );
  });

  testWidgets('the word card opens its construct detail', (tester) async {
    final router = await pumpOverOverlay(
      tester,
      Material(
        child: Builder(
          builder: (cardContext) => TextButton(
            onPressed: () => AnalyticsNavigationUtil.navigateToAnalytics(
              context: cardContext,
              view: ProgressIndicatorEnum.wordsUsed,
              construct: ConstructIdentifier(
                lemma: 'hund',
                type: ConstructTypeEnum.vocab,
                category: 'NOUN',
              ),
            ),
            child: const Text('hund'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('hund'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      isNot('/rooms'),
      reason: 'the tap must move the workspace URL, not die silently',
    );
  });

  testWidgets('the word card unlocks transcriptions from inside an overlay', (
    tester,
  ) async {
    // The word card's phonetic transcription offers its own gate: on a 401 the
    // strip becomes "subscribe to unlock transcriptions", and tapping it went
    // to subscription settings through `GoRouterState.of`. The card is an
    // overlay entry on both of its hosts — the chat toolbar's word card and the
    // activity vocab chip's — so that read threw and the gate did nothing.
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'syt_test_token',
    );
    final client = MockClient(
      (_) async => Response(
        jsonEncode({'detail': 'No active subscription found'}),
        401,
        headers: {'content-type': 'application/json'},
      ),
    );

    await runWithClient(() async {
      final router = await pumpOverOverlay(
        tester,
        Material(
          child: PhoneticTranscriptionWidget(
            text: 'Hund',
            textLanguage: LanguageModel(langCode: 'de', displayName: 'German'),
            pos: 'NOUN',
            roomId: null,
          ),
        ),
        settle: false,
      );
      // The 401 has to land before the gate exists to be tapped. The repo
      // opens its disk cache first, which is real I/O the fake clock will not
      // advance — hence `runAsync` — and the strip shimmers throughout, so
      // `pumpAndSettle` would time out rather than reach the gate.
      for (var i = 0; i < 40; i++) {
        if (find.byType(ErrorIndicator).evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 20)),
        );
        // With a duration: `GetStorage` opens the cache box on a zero-duration
        // timer, which only fires when the test clock moves.
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Named, not just any `ErrorIndicator`: the widget shows a second,
      // untappable one for an ordinary fetch failure, and tapping that would
      // fail this test for the wrong reason.
      expect(
        find.textContaining(
          'Subscribe to unlock transcriptions',
          findRichText: true,
        ),
        findsOneWidget,
        reason: 'the 401 must surface as the unlock gate, not a bare failure',
      );
      await tester.tap(find.byType(ErrorIndicator));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        contains('settingspage:subscription'),
      );
    }, () => client);
  });

  testWidgets('a matrix pill in an overlay message opens its profile', (
    tester,
  ) async {
    // The toolbar overlay renders its own copy of the message
    // (`OverlayMessage` -> `MessageContent` -> `HtmlMessage`), so a mention
    // pill inside a selected message is mounted in the overlay. Its tap handler
    // read the current URI to hand to `UserDialog`, and awaited a profile
    // lookup first — so the throw landed in an async gap and the pill was inert.
    final router = await pumpOverOverlay(
      tester,
      Material(
        child: Builder(
          builder: (cardContext) => MatrixPill(
            name: 'Alice',
            outerContext: cardContext,
            uri: 'https://matrix.to/#/@alice:fakeServer.notExisting',
            fontSize: 14.0,
            color: Colors.blue,
            userId: '@alice:fakeServer.notExisting',
          ),
        ),
      ),
      wrap: (app) => _TestMatrix(clients: [client], store: store, child: app),
      // The pill's avatar animates while it loads, so the tree never settles.
      settle: false,
    );

    await tester.tap(find.byType(MatrixPill));
    // The handler awaits a profile lookup against the fake homeserver before it
    // reads the URI, so give that real round trip time to land.
    for (var i = 0; i < 40; i++) {
      if (find.byType(UserDialog).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(
      find.byType(UserDialog),
      findsOneWidget,
      reason: 'the pill must open the profile, not die in its async gap',
    );
    expect(router.routeInformationProvider.value.uri.toString(), isNotEmpty);
  });
}

/// Skips `initMatrix()` — these tests need the client back out of the tree
/// (`Matrix.of(context).client`), not a booted app.
class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {
    MatrixState.pangeaController = FakePangeaController();
  }
}

class _TestMatrix extends Matrix {
  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}
