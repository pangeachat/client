import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_card.dart';

/// #8957 — the writing assistance card sits over a composer the learner is
/// usually still focused in, so on mobile the keyboard is up while they read
/// it. The overflow menu pushes a route, which drops the keyboard; without
/// help, popping that route hands focus straight back and the keyboard springs
/// up again. One tap on the menu cost the learner a full close-and-open
/// animation.
///
/// `SpanCardState._onOpenMenu` unfocuses the composer on `onOpenMenu`. This
/// pins down what that is worth: the menu's route must not undo it. The
/// composer here stands in for the chat's input bar.
void main() {
  Future<void> pumpCard(WidgetTester tester, FocusNode composer) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 400,
                child: SpanCardHeader(
                  targetId: 'wa-listen-test',
                  title: 'Spelling',
                  showListenFirst: true,
                  listenFirst: false,
                  autoIGC: true,
                  onToggleListenFirst: (_) {},
                  onToggleAutoIGC: () {},
                  onFeedback: () {},
                  onLearningSettings: () {},
                  onClose: () {},
                  // What SpanCardState does with the choreographer's input
                  // focus node.
                  onOpenMenu: composer.unfocus,
                ),
              ),
              TextField(focusNode: composer),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the keyboard goes down for the menu and stays down', (
    tester,
  ) async {
    final composer = FocusNode();
    addTearDown(composer.dispose);

    await pumpCard(tester, composer);
    composer.requestFocus();
    await tester.pumpAndSettle();
    expect(composer.hasFocus, isTrue, reason: 'the learner was typing');

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Learning settings'), findsOneWidget);
    expect(composer.hasFocus, isFalse, reason: 'the keyboard drops');

    // Dismissing the menu by its barrier is the "click off menu" of the issue;
    // choosing an entry pops the same route the same way.
    // Bottom-left of the 800x600 test surface — clear of the menu, which
    // hangs off the button at the header's right edge.
    await tester.tapAt(const Offset(5, 590));
    await tester.pumpAndSettle();
    expect(find.text('Learning settings'), findsNothing);
    expect(
      composer.hasFocus,
      isFalse,
      reason: 'the closing menu must not bring the keyboard back',
    );
  });
}
