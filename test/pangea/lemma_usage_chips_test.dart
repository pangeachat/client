import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/lemma_usage_chips.dart';

/// The usage row is one chip per score bucket, counted over ALL uses.
/// Exposure fires often enough that counting it as a use would bury everything
/// the learner earned, so it is excluded by type and shown as its own heard
/// chip — the regression these tests exist to prevent.
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

  LemmaUsageChips chipsFor(List<OneConstructUse> uses) => LemmaUsageChips(
    construct: ConstructUses(
      uses: uses,
      constructType: ConstructTypeEnum.vocab,
      lemma: 'hablar',
      category: 'verb',
    ),
    category: LearningSkillsEnum.hearing,
    tooltip: '',
    icon: Icons.volume_up,
  );

  UsageChipCounts countsFor(
    List<OneConstructUse> uses,
    LearningSkillsEnum skill,
  ) => chipsFor(uses).useCounts(skill);

  int heardFor(List<OneConstructUse> uses, LearningSkillsEnum skill) =>
      chipsFor(uses).exposureCount(skill);

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

  group('the use counts', () {
    test('bucket by score', () {
      final counts = countsFor([
        use(ConstructUseTypeEnum.corLA),
        use(ConstructUseTypeEnum.corLA),
        use(ConstructUseTypeEnum.incLA),
        use(ConstructUseTypeEnum.ignWL),
      ], LearningSkillsEnum.hearing);

      expect(counts.positive, 2);
      expect(counts.negative, 1);
      expect(counts.neutral, 1);
    });

    test('exclude exposure, however much of it there is', () {
      final counts = countsFor([
        use(ConstructUseTypeEnum.hrd, count: 200),
        use(ConstructUseTypeEnum.hrd, count: 40),
      ], LearningSkillsEnum.hearing);

      expect(counts.isEmpty, isTrue, reason: 'exposure is not a use');
    });

    test('keep counting past the flower cap', () {
      // The dots this replaced drew from `cappedUses` and silently froze at
      // flowering. A counter frozen at "×34" reads as broken, so chips count
      // everything.
      final uses = [
        for (var i = 0; i < 60; i++) use(ConstructUseTypeEnum.corPA),
      ];

      expect(countsFor(uses, LearningSkillsEnum.reading).positive, 60);
    });

    test('count other zero-XP uses as neutral', () {
      // The rule is "every use counts EXCEPT exposure", not "counts are scored
      // uses". Dropping every 0-XP use would take real evidence with it.
      final counts = countsFor([
        use(ConstructUseTypeEnum.corWL),
        use(ConstructUseTypeEnum.ignWL),
      ], LearningSkillsEnum.hearing);

      expect(counts.positive, 1);
      expect(counts.neutral, 1);
    });

    test('keep a word typed correctly in chat on the writing row', () {
      // ignIGC is minted on every sent message for tokens writing assistance
      // left alone, so it is the bulk of the Writing row's neutral count. An
      // exclusion by score rather than by type made this row read as empty.
      final counts = countsFor([
        use(ConstructUseTypeEnum.ignIGC),
        use(ConstructUseTypeEnum.ignIGC),
      ], LearningSkillsEnum.writing);

      expect(counts.neutral, 2);
    });

    test('exclude exposure even alongside other zero-XP uses', () {
      final counts = countsFor([
        use(ConstructUseTypeEnum.ignWL),
        use(ConstructUseTypeEnum.hrd, count: 400),
      ], LearningSkillsEnum.hearing);

      expect(counts.neutral, 1, reason: 'the ignored hint, not the hearings');
    });

    test('do not leak a use into another skill row', () {
      final counts = countsFor([
        use(ConstructUseTypeEnum.hrd, count: 12),
        use(ConstructUseTypeEnum.click),
      ], LearningSkillsEnum.reading);

      expect(counts.positive, 1);
      expect(counts.neutral, 0);
      expect(
        countsFor([
          use(ConstructUseTypeEnum.hrd, count: 12),
        ], LearningSkillsEnum.hearing).isEmpty,
        isTrue,
      );
    });
  });
}
