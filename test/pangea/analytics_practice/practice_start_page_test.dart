import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_skills_store.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_start_page.dart';

/// The start page every fresh practice session opens on
/// (practice-exercises.instructions.md, "Start page").
void main() {
  late List<Set<LearningSkillsEnum>> changes;
  late int starts;

  setUp(() {
    changes = [];
    starts = 0;
  });

  Future<void> pump(
    WidgetTester tester, {
    ConstructTypeEnum type = ConstructTypeEnum.vocab,
    Set<LearningSkillsEnum> skills = PracticeSkillsStore.vocabSkills,
    Set<LearningSkillsEnum> available = PracticeSkillsStore.vocabSkills,
    bool picking = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: PracticeStartPage(
            type: type,
            count: 8,
            emojis: type == ConstructTypeEnum.vocab ? const ['🍎', '🚲'] : [],
            skills: skills,
            availableSkills: available,
            onSkillsChanged: changes.add,
            onStart: picking ? null : () => starts++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder chip(String label) => find.widgetWithText(FilterChip, label);

  testWidgets('vocab shows the count, emojis, chips and Start', (tester) async {
    await pump(tester);

    expect(find.text('8'), findsOneWidget);
    expect(find.text('words to practice'), findsOneWidget);
    expect(find.text('🍎'), findsOneWidget);
    expect(find.text('🚲'), findsOneWidget);
    for (final label in ['Reading', 'Listening', 'Speaking']) {
      expect(tester.widget<FilterChip>(chip(label)).selected, isTrue);
    }

    await tester.tap(find.text('Start'));
    expect(starts, 1);
  });

  testWidgets('turning a chip off asks for the remaining types', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(chip('Speaking'));
    expect(changes, [
      {LearningSkillsEnum.reading, LearningSkillsEnum.hearing},
    ]);
  });

  testWidgets('the last chip on stays on', (tester) async {
    await pump(tester, skills: {LearningSkillsEnum.hearing});

    await tester.tap(chip('Listening'));
    expect(changes, isEmpty);

    await tester.tap(chip('Speaking'));
    expect(changes, [
      {LearningSkillsEnum.hearing, LearningSkillsEnum.speaking},
    ]);
  });

  testWidgets('a type with no words is disabled', (tester) async {
    await pump(
      tester,
      skills: {LearningSkillsEnum.reading},
      available: {LearningSkillsEnum.reading},
    );

    expect(tester.widget<FilterChip>(chip('Speaking')).onSelected, isNull);
    expect(tester.widget<FilterChip>(chip('Listening')).onSelected, isNull);
    expect(tester.widget<FilterChip>(chip('Reading')).onSelected, isNotNull);
  });

  testWidgets('Start waits while the words are picked again', (tester) async {
    await pump(tester, picking: true);

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('grammar shows its count and no chips', (tester) async {
    await pump(tester, type: ConstructTypeEnum.morph);

    expect(find.text('grammar points to practice'), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('Start'), findsOneWidget);
  });
}
