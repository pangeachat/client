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
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_vocab_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'get_test_client.dart';
import 'word_card_test_matrix.dart';

/// #8620 — a pointer never got a second tap on a vocab chip whose card was
/// open: the tap landed on the card's backdrop and dismissed it. A screen
/// reader did, activating the chip straight through the semantics tree, and
/// re-opening an already-open overlay key is a no-op — so the card had no way
/// to close. Selecting the open chip again must close its card.
///
/// #9122 — a pointer now reaches a chip through the open card's backdrop too,
/// via a tap target laid over each chip inside the overlay, so one tap moves
/// the card from chip to chip. The last test drives that path by position.
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
      WordCardTestMatrix(
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

  /// Sentry CLIENT-EPV (#9052). The card opens from a post-frame callback that
  /// reads `context`; when the chip is disposed between the tap and that frame
  /// — the session ends, the learner backs out — `State.context` threw on the
  /// dead element. There is no card to position at that point, so the callback
  /// must simply return.
  testWidgets('a chip disposed before its frame does not throw', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpVocab(tester);

      // Activated WITHOUT pumping, so the post-frame callback is queued and
      // has not run yet — the window the crash lives in.
      final node = tester.semantics.find(
        find.descendant(
          of: find.byType(ActivityVocabWidget),
          matching: find.ancestor(
            of: find.text(vocab.first.lemma, findRichText: true),
            matching: find.byType(InkWell),
          ),
        ),
      );
      node.owner!.performAction(node.id, SemanticsAction.tap);

      // The session goes away under the learner before that frame arrives.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
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

  /// A pointer's path (#9122), placed at the chip's position rather than on
  /// the chip widget: with a card open the chip sits under the overlay, and
  /// what the tap lands on is the point — the chip's tap target above the
  /// card's backdrop, not the backdrop. The hit test here is Flutter's; a
  /// widget test cannot see the web semantics DOM, so that half of the fix is
  /// verified on the preview build.
  Future<void> tapAtChip(WidgetTester tester, Vocab v) async {
    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(ActivityVocabWidget),
          matching: find.ancestor(
            of: find.text(v.lemma, findRichText: true),
            matching: find.byType(InkWell),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('one tap moves the card from one chip to another', (
    tester,
  ) async {
    await pumpVocab(tester);

    await tapAtChip(tester, vocab.first);
    expect(cardIsOpen(vocab.first), isTrue, reason: 'a tap opens the card');

    await tapAtChip(tester, vocab.last);
    expect(
      cardIsOpen(vocab.first),
      isFalse,
      reason: 'the tap reached the other chip and closed this card',
    );
    expect(
      cardIsOpen(vocab.last),
      isTrue,
      reason: "and opened the other chip's card from that one tap",
    );

    await tapAtChip(tester, vocab.last);
    expect(
      cardIsOpen(vocab.last),
      isFalse,
      reason: 'a tap on the open chip closes its card',
    );
    expect(cardIsOpen(vocab.first), isFalse, reason: 'and nothing reopens');

    await tapAtChip(tester, vocab.first);
    expect(cardIsOpen(vocab.first), isTrue);
    // Off the row entirely: the backdrop, and only the backdrop.
    await tester.tapAt(
      tester.getBottomRight(find.byType(Scaffold)) - const Offset(5, 5),
    );
    await tester.pump();
    await tester.pump();
    expect(
      cardIsOpen(vocab.first),
      isFalse,
      reason: 'a tap away from the chips still dismisses',
    );

    // See withVocab: let the repos' storage timer fire before the test ends.
    await tester.pump(const Duration(seconds: 1));
  });
}
