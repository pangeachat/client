import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/choice_cards/game_choice_card.dart';

/// A card rebuilt after the practice panel closed must come back showing the
/// choice the learner already picked — the selection is session state, not
/// card state (#8309).
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required bool isSelected,
    bool shouldFlip = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GameChoiceCard(
          targetId: 'target',
          onPressed: () {},
          isCorrect: false,
          isSelected: isSelected,
          shouldFlip: shouldFlip,
          altChild: const Text('revealed'),
          child: const Text('choice'),
        ),
      ),
    ),
  );

  Color? tintOf(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(GameChoiceCard),
        matching: find.byType(Container),
      ),
    );
    return (container.foregroundDecoration as BoxDecoration?)?.color;
  }

  group('GameChoiceCard', () {
    testWidgets('an unselected choice is untinted', (tester) async {
      await pumpCard(tester, isSelected: false);
      expect(tintOf(tester), Colors.transparent);
    });

    testWidgets('a choice selected earlier in the session is tinted on first '
        'build', (tester) async {
      await pumpCard(tester, isSelected: true);
      expect(tintOf(tester), AppConfig.error.withValues(alpha: 0.3));
    });

    testWidgets('a flip card selected earlier rebuilds already revealed', (
      tester,
    ) async {
      await pumpCard(tester, isSelected: true, shouldFlip: true);
      expect(find.text('revealed'), findsOneWidget);
      expect(find.text('choice'), findsNothing);
    });

    testWidgets('tapping tints the card', (tester) async {
      await pumpCard(tester, isSelected: false);
      await tester.tap(find.byType(GameChoiceCard));
      await tester.pump();
      expect(tintOf(tester), AppConfig.error.withValues(alpha: 0.3));
    });
  });
}
