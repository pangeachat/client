import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_vocab_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #8620 — a pointer never gets a second tap on a vocab chip whose card is
/// open: the tap lands on the card's backdrop and dismisses it. A screen
/// reader does, activating the chip straight through the semantics tree, and
/// re-opening an already-open overlay key is a no-op — so the card had no way
/// to close. Selecting the open chip again must close its card.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const targetId = 'activity-vocab-target';
  final vocab = [
    Vocab(lemma: 'perro', pos: 'NOUN'),
    Vocab(lemma: 'gato', pos: 'NOUN'),
  ];

  String overlayKeyFor(Vocab v) => '$targetId-${v.lemma}';

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('activity_vocab');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    // The chip speaks its lemma on open; the engine is not under test here.
    // The `get*` queries must answer with a list — the plugin's dynamic
    // returns are cast, and a cast failure lands in an error handler that
    // breaks into the debugger and hangs the run.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
          methodCall,
        ) async {
          return methodCall.method.startsWith('get') ? [] : 1;
        });
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeServer.notExisting'},
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    MatrixState.pAnyState.closeAllOverlays(force: true);
    await client.dispose();
  });

  /// English throughout — one locale per isolate, or a second set of delegates
  /// loads asynchronously and leaves the subtree empty for the pumped frames.
  Future<void> pumpVocab(WidgetTester tester) async {
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: ActivityVocabWidget(
              vocab: vocab,
              langCode: 'es',
              targetId: targetId,
              activityLangCode: 'es',
              usedVocab: null,
              roomId: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Pumps the widget with the semantics tree on — it is off by default in
  /// tests, and the handle has to be released before the body returns, so the
  /// body runs inside this.
  Future<void> withVocab(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpVocab(tester);
      await body();
      // The card's repos open a GetStorage box on a zero-duration timer the
      // first time they are touched; let it fire rather than end the test with
      // a timer pending.
      await tester.pump(const Duration(seconds: 1));
    } finally {
      semantics.dispose();
    }
  }

  /// What a screen reader does: activate the chip's own semantics node. A
  /// pointer cannot reach the chip while a card is open — its press lands on
  /// the card's backdrop and dismisses it — so driving this with `tap` would
  /// exercise the backdrop, not the bug.
  Future<void> activateChip(WidgetTester tester, Vocab v) async {
    final node = tester.semantics.find(
      find.descendant(
        of: find.byType(ActivityVocabWidget),
        // The open card shows the lemma too, so the chip has to be named by
        // where it sits, not by its text alone.
        matching: find.ancestor(
          of: find.text(v.lemma, findRichText: true),
          matching: find.byType(InkWell),
        ),
      ),
    );
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pump();
    await tester.pump();
  }

  bool cardIsOpen(Vocab v) =>
      MatrixState.pAnyState.isOverlayOpen(overlayKey: overlayKeyFor(v));

  testWidgets('selecting the same chip twice opens then closes its card', (
    tester,
  ) async {
    await withVocab(tester, () async {
      await activateChip(tester, vocab.first);
      expect(
        cardIsOpen(vocab.first),
        isTrue,
        reason: 'the first activation opens the word card',
      );

      await activateChip(tester, vocab.first);
      expect(
        cardIsOpen(vocab.first),
        isFalse,
        reason: 'the second activation closes it again',
      );

      await activateChip(tester, vocab.first);
      expect(
        cardIsOpen(vocab.first),
        isTrue,
        reason: 'and a third re-opens it — the toggle does not latch closed',
      );
    });
  });

  testWidgets(
    'selecting another chip moves the card rather than stacking one',
    (tester) async {
      await withVocab(tester, () async {
        await activateChip(tester, vocab.first);
        await activateChip(tester, vocab.last);

        expect(
          cardIsOpen(vocab.first),
          isFalse,
          reason: 'the previously open card closes (#8279)',
        );
        expect(cardIsOpen(vocab.last), isTrue);
      });
    },
  );
}

/// Skips `initMatrix()`, and serves an analytics service that never finishes
/// initializing — the branch where the new-token lookup returns nothing, so no
/// database is opened for a test about overlay lifetime.
class _TestMatrixState extends MatrixState {
  final AnalyticsDataService _service = _FakeAnalyticsDataService();

  @override
  // ignore: must_call_super
  void initState() {
    // `initMatrix` normally assigns this; the new-token lookup reads the
    // analytics service back through it.
    MatrixState.pangeaController = _VocabTestController(this);
  }

  @override
  AnalyticsDataService get analyticsDataService => _service;
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

/// [FakePangeaController] plus the two controllers this surface reads back
/// through the static: the word card asks the subscription controller whether
/// to render its content, and the TTS path asks the user controller for the L2.
class _VocabTestController implements PangeaController {
  _VocabTestController(this.matrixState);

  @override
  final MatrixState matrixState;

  final PangeaController _delegate = FakePangeaController(userL1Code: 'en');

  @override
  UserController get userController => _delegate.userController;

  @override
  final SubscriptionController subscriptionController =
      _FakeSubscriptionController();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSubscriptionController implements SubscriptionController {
  @override
  bool get showSubscriptionGatedContent => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAnalyticsDataService implements AnalyticsDataService {
  @override
  late final AnalyticsUpdateDispatcher updateDispatcher =
      AnalyticsUpdateDispatcher(this);

  @override
  bool get isInitializing => true;

  @override
  bool isConstructBlocked(ConstructIdentifier id) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
