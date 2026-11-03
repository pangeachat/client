import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/construct_practice_extension.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';

ConstructUses _construct(String lemma, DateTime lastMeaningPractice) =>
    ConstructUses(
      uses: [
        OneConstructUse(
          useType: ConstructUseTypeEnum.corLM,
          lemma: lemma,
          constructType: ConstructTypeEnum.vocab,
          metadata: ConstructUseMetaData(
            roomId: null,
            timeStamp: lastMeaningPractice,
          ),
          category: 'noun',
          form: lemma,
          xp: ConstructUseTypeEnum.corLM.pointValue,
        ),
      ],
      constructType: ConstructTypeEnum.vocab,
      lemma: lemma,
      category: 'noun',
    );

/// Words with the same priority come in a random order, so sessions do not
/// keep drawing the same ones (practice-exercises.instructions.md,
/// "Standalone Practice — practice sorting").
void main() {
  final longAgo = DateTime.now().subtract(const Duration(days: 30));
  final tied = [for (var i = 0; i < 8; i++) _construct('tied$i', longAgo)];
  final recent = _construct('recent', DateTime.now());
  final constructs = [recent, ...tied];

  List<String> order(int seed) => [
    for (final c in constructs.practiceSort(
      PracticeExerciseTypeEnum.lemmaMeaning,
      random: Random(seed),
    ))
      c.lemma,
  ];

  test('a lower priority still comes after every higher one', () {
    for (var seed = 0; seed < 20; seed++) {
      expect(order(seed).last, 'recent');
    }
  });

  test('tied words do not always come in the same order', () {
    final firsts = {for (var seed = 0; seed < 20; seed++) order(seed).first};
    expect(firsts.length, greaterThan(1));
  });
}
