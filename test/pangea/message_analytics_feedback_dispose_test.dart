import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/message_analytics_feedback.dart';

/// CLIENT-CYK (#9070): the "+N" bubble scheduled its numbers animation 400 ms
/// out with a bare `Future.delayed`, and the overlay it lives in can be torn
/// down inside that window — the callback then drove a disposed controller.
/// Reaching the end of each test without an error from
/// `AnimationController.stop` is the assertion.
void main() {
  setUpAll(() async {
    await lookupL10n(const Locale('en'));
  });

  Future<void> pumpBubble(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: MessageAnalyticsFeedback(
          newGrammarConstructs: 2,
          newVocabConstructs: 3,
          close: () {},
        ),
      ),
    ),
  );

  testWidgets('a bubble torn down inside 400 ms leaves no delayed animation', (
    tester,
  ) async {
    await pumpBubble(tester);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const SizedBox.shrink());
    // Run past both delays: the 400 ms numbers start and the 4 s close.
    await tester.pump(const Duration(seconds: 5));
  });
}
