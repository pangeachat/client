import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/construct_practice_extension.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

class VocabMeaningTargetGenerator {
  static PracticeExerciseTypeEnum exerciseType =
      PracticeExerciseTypeEnum.lemmaMeaning;

  static Future<List<AnalyticsPracticeTarget>> get(
    List<ConstructUses> constructs,
  ) async {
    // Score and sort by priority (highest first). Uses shared scorer for
    // consistent prioritization with message practice.
    final sortedConstructs = constructs.practiceSort(exerciseType);

    final Set<String> seenLemmas = {};

    final targets = <AnalyticsPracticeTarget>[];
    for (final construct in sortedConstructs) {
      if (seenLemmas.contains(construct.lemma)) continue;

      if (construct.shouldSkipForRecentPractice(exerciseType)) {
        continue;
      }

      seenLemmas.add(construct.lemma);

      if (!construct.cappedUses.any(
        (u) => u.metadata.eventId != null && u.metadata.roomId != null,
      )) {
        // Skip if no uses have eventId + roomId, so example message can be fetched.
        continue;
      }

      targets.add(
        AnalyticsPracticeTarget(
          target: PracticeTarget(
            tokens: [construct.id.asToken],
            exerciseType: exerciseType,
          ),
        ),
      );
      if (targets.length >= AnalyticsPracticeConstants.targetsToGenerate) {
        break;
      }
    }
    return targets;
  }
}
