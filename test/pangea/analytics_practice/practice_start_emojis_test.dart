import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_start_emojis.dart';

ConstructIdentifier _word(String lemma) => ConstructIdentifier(
  lemma: lemma,
  type: ConstructTypeEnum.vocab,
  category: 'noun',
);

/// The start page's emoji row: the learner's emoji, else the dictionary's,
/// fetched when not saved, with a slot held per word while fetches run
/// (practice-exercises.instructions.md, "Start page").
void main() {
  late Map<String, String?> saved;
  late Map<String, Completer<String?>> fetches;

  setUp(() {
    saved = {};
    fetches = {};
  });

  Future<void> pump(
    WidgetTester tester,
    List<String> lemmas, {
    bool offline = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeStartEmojis(
            words: [for (final lemma in lemmas) _word(lemma)],
            offline: offline,
            savedEmojiOf: (word) => saved[word.lemma],
            fetchEmojiOf: (word) =>
                (fetches[word.lemma] = Completer<String?>()).future,
          ),
        ),
      ),
    );
  }

  final placeholders = find.byWidgetPredicate(
    (w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).shape == BoxShape.circle,
  );

  testWidgets('saved emojis show at once and nothing is fetched', (
    tester,
  ) async {
    saved = {'a': '🍎', 'b': '🚲'};
    await pump(tester, ['a', 'b']);

    expect(find.text('🍎'), findsOneWidget);
    expect(find.text('🚲'), findsOneWidget);
    expect(placeholders, findsNothing);
    expect(fetches, isEmpty);
  });

  testWidgets('a missing emoji holds a slot until it is fetched', (
    tester,
  ) async {
    saved = {'a': '🍎'};
    await pump(tester, ['a', 'b']);

    expect(fetches.keys, ['b']);
    expect(placeholders, findsOneWidget);

    fetches['b']!.complete('🚲');
    await tester.pumpAndSettle();
    expect(find.text('🚲'), findsOneWidget);
    expect(placeholders, findsNothing);
  });

  testWidgets('a word with no emoji drops out once every fetch settles', (
    tester,
  ) async {
    await pump(tester, ['a', 'b']);
    expect(placeholders, findsNWidgets(2));

    fetches['a']!.complete(null);
    await tester.pumpAndSettle();
    // Still holding both places while b loads.
    expect(placeholders, findsNWidgets(2));

    fetches['b']!.complete('☕');
    await tester.pumpAndSettle();
    expect(find.text('☕'), findsOneWidget);
    expect(placeholders, findsNothing);
  });

  testWidgets('offline only saved emojis are used', (tester) async {
    saved = {'a': '🍎'};
    await pump(tester, ['a', 'b'], offline: true);

    expect(find.text('🍎'), findsOneWidget);
    expect(placeholders, findsNothing);
    expect(fetches, isEmpty);
  });
}
