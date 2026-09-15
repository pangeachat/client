import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/lemma_usage_dots.dart';

/// The usage row is one mark per SCORED use. Exposure fires often enough that
/// drawing a mark for it would bury everything the learner earned under a wall
/// of identical dots — the regression this exclusion exists to prevent.
void main() {
  OneConstructUse use(ConstructUseTypeEnum type, {int? count}) =>
      OneConstructUse(
        useType: type,
        lemma: 'hablar',
        constructType: ConstructTypeEnum.vocab,
        category: 'verb',
        form: 'hablar',
        xp: type.pointValue,
        count: count ?? 1,
        metadata: ConstructUseMetaData(
          roomId: null,
          timeStamp: DateTime.utc(2026, 8, 24, 9),
        ),
      );

  List<Color> marksFor(List<OneConstructUse> uses, LearningSkillsEnum skill) {
    return LemmaUsageDots(
      construct: ConstructUses(
        uses: uses,
        constructType: ConstructTypeEnum.vocab,
        lemma: 'hablar',
        category: 'verb',
      ),
      category: skill,
      tooltip: '',
      icon: Icons.volume_up,
    ).sortedUses(skill);
  }

  int heardFor(List<OneConstructUse> uses, LearningSkillsEnum skill) {
    return LemmaUsageDots(
      construct: ConstructUses(
        uses: uses,
        constructType: ConstructTypeEnum.vocab,
        lemma: 'hablar',
        category: 'verb',
      ),
      category: skill,
      tooltip: '',
      icon: Icons.volume_up,
    ).exposureCount(skill);
  }

  group('the heard count', () {
    test('sums occurrences, not rows', () {
      // One row stands for a whole window of hearings. Counting rows would
      // report a number far below what happened.
      expect(
        heardFor([
          use(ConstructUseTypeEnum.hrd, count: 40),
          use(ConstructUseTypeEnum.hrd, count: 2),
        ], LearningSkillsEnum.hearing),
        42,
      );
    });

    test('is zero when the learner has heard nothing', () {
      expect(
        heardFor([use(ConstructUseTypeEnum.corLA)], LearningSkillsEnum.hearing),
        0,
      );
    });

    test('does not appear on a row that is not listening', () {
      expect(
        heardFor([
          use(ConstructUseTypeEnum.hrd, count: 9),
        ], LearningSkillsEnum.reading),
        0,
      );
    });

    test('keeps counting past the flower cap', () {
      // `cappedUses` stops at the XP cap, so a capped figure would freeze at
      // flowering — under-reporting exposure for the words heard most. Enough
      // scored uses here to pass the cap, then more hearings after it.
      final uses = [
        for (var i = 0; i < 30; i++) use(ConstructUseTypeEnum.corPA),
        use(ConstructUseTypeEnum.hrd, count: 12),
      ];

      expect(heardFor(uses, LearningSkillsEnum.hearing), 12);
    });
  });

  test('exposure draws no mark, however much of it there is', () {
    final marks = marksFor([
      use(ConstructUseTypeEnum.hrd, count: 200),
      use(ConstructUseTypeEnum.hrd, count: 40),
    ], LearningSkillsEnum.hearing);

    expect(marks, isEmpty);
  });

  test('scored listening uses still draw, alongside exposure', () {
    final marks = marksFor([
      use(ConstructUseTypeEnum.corLA),
      use(ConstructUseTypeEnum.hrd, count: 86),
      use(ConstructUseTypeEnum.incLA),
    ], LearningSkillsEnum.hearing);

    expect(marks, [AppConfig.success, Colors.red]);
  });

  test('other zero-XP uses still draw their grey mark', () {
    // The rule is "every use is a mark EXCEPT exposure", not "marks are scored
    // uses". Dropping every 0-XP use would take real evidence with it.
    final marks = marksFor([
      use(ConstructUseTypeEnum.corWL),
      use(ConstructUseTypeEnum.ignWL),
    ], LearningSkillsEnum.hearing);

    expect(marks, hasLength(2));
    expect(marks.first, AppConfig.success);
  });

  test('a word typed correctly in chat keeps its writing marks', () {
    // ignIGC is minted on every sent message for tokens writing assistance
    // left alone, so it is the most common thing in the Writing row. An
    // exclusion by score rather than by type made this row read as empty.
    final marks = marksFor([
      use(ConstructUseTypeEnum.ignIGC),
      use(ConstructUseTypeEnum.ignIGC),
    ], LearningSkillsEnum.writing);

    expect(marks, hasLength(2));
  });

  test('exposure is excluded even alongside other zero-XP uses', () {
    final marks = marksFor([
      use(ConstructUseTypeEnum.ignWL),
      use(ConstructUseTypeEnum.hrd, count: 400),
    ], LearningSkillsEnum.hearing);

    expect(marks, hasLength(1), reason: 'the ignored hint, not the hearings');
  });

  test('exposure does not leak into another skill row', () {
    final marks = marksFor([
      use(ConstructUseTypeEnum.hrd, count: 12),
      use(ConstructUseTypeEnum.click),
    ], LearningSkillsEnum.reading);

    expect(marks, [AppConfig.success]);
    expect(
      marksFor([
        use(ConstructUseTypeEnum.hrd, count: 12),
      ], LearningSkillsEnum.hearing),
      isEmpty,
    );
  });
}
