import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/choice_cards/meaning_choice_card.dart';

/// A meaning choice without an emoji, common in an offline session (#9513),
/// lines its text up with the choices that have one rather than starting at
/// the card's edge.
void main() {
  testWidgets('a choice without an emoji lines up with one that has an emoji', (
    tester,
  ) async {
    MeaningChoiceCard card(String lemma, String meaning, {String? emoji}) =>
        MeaningChoiceCard(
          choiceId: ConstructIdentifier(
            lemma: lemma,
            type: ConstructTypeEnum.vocab,
            category: 'noun',
          ).string,
          targetId: lemma,
          displayText: meaning,
          emoji: emoji,
          onPressed: () {},
          isCorrect: false,
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              card('perro', 'dog', emoji: '🐶'),
              card('eso', 'that'),
              card('para', 'for', emoji: ''),
            ],
          ),
        ),
      ),
    );

    final withEmoji = tester.getTopLeft(find.text('dog')).dx;
    expect(tester.getTopLeft(find.text('that')).dx, withEmoji);
    expect(tester.getTopLeft(find.text('for')).dx, withEmoji);
    expect(withEmoji, greaterThan(0));
  });
}
