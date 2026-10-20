import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';

/// The read-aloud use types join voice messages and calls as speaking, a
/// heard target earns what a listening answer earns, and a miss costs nothing
/// (practice-exercises.instructions.md, "Scoring").
void main() {
  test('read-aloud uses are speaking', () {
    expect(
      ConstructUseTypeEnum.corRA.skillsEnumType,
      LearningSkillsEnum.speaking,
    );
    expect(
      ConstructUseTypeEnum.incRA.skillsEnumType,
      LearningSkillsEnum.speaking,
    );
  });

  test('a heard target earns a listening answer\'s XP and a miss earns 0', () {
    expect(
      ConstructUseTypeEnum.corRA.pointValue,
      ConstructUseTypeEnum.corLA.pointValue,
    );
    expect(ConstructUseTypeEnum.incRA.pointValue, 0);
    expect(ConstructUseTypeEnum.incRA.isIncorrectPractice, isTrue);
    expect(ConstructUseTypeEnum.corRA.sentByUser, isFalse);
  });

  test(
    'the read-aloud exercise maps to its use types and is vocab practice',
    () {
      const type = PracticeExerciseTypeEnum.readAloud;
      expect(type.correctUse, ConstructUseTypeEnum.corRA);
      expect(type.incorrectUse, ConstructUseTypeEnum.incRA);
      expect(PracticeExerciseTypeEnum.fromString('read_aloud'), type);
      expect(type.includeTTSOnClick, isFalse);
    },
  );
}
