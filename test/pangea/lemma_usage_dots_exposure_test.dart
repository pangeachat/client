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

  test('other zero-XP uses are excluded too, not just exposure', () {
    // The rule is "marks are scored uses", not "marks are everything but the
    // new thing" — an ignored hint is no more a mark than a hearing is.
    final marks = marksFor([
      use(ConstructUseTypeEnum.corWL),
      use(ConstructUseTypeEnum.ignWL),
    ], LearningSkillsEnum.hearing);

    expect(marks, [AppConfig.success]);
  });

  test('exposure does not leak into another skill row', () {
    final marks = marksFor([
      use(ConstructUseTypeEnum.hrd, count: 12),
      use(ConstructUseTypeEnum.click),
    ], LearningSkillsEnum.reading);

    expect(marks, [AppConfig.success]);
  });
}
