import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/construct_practice_extension.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

class VocabAudioTargetGenerator {
  static PracticeExerciseTypeEnum exerciseType =
      PracticeExerciseTypeEnum.lemmaAudio;

  static Future<List<AnalyticsPracticeTarget>> get(
    List<ConstructUses> constructs,
  ) async {
    // Score and sort by priority (highest first). Uses shared scorer for
    // consistent prioritization with message practice.
    final sortedConstructs = constructs.practiceSort(exerciseType);

    final Set<String> seenLemmas = {};

    final targets = <AnalyticsPracticeTarget>[];

    for (final construct in sortedConstructs) {
      if (targets.length >= AnalyticsPracticeConstants.targetsToGenerate) {
        break;
      }

      if (seenLemmas.contains(construct.lemma)) continue;

      if (construct.shouldSkipForRecentPractice(exerciseType)) {
        continue;
      }

      // Cheap local check that an audio example is *resolvable* — a use that
      // points at a message (eventId + roomId). The example message itself is
      // resolved later, at generation, off the critical path (#7702): doing it
      // here forced N serial event fetches before the first exercise could
      // show. An audio target that fails to resolve at generation falls back
      // to a meaning exercise (VocabAudioPracticeExerciseGenerator).
      if (!construct.cappedUses.any(
        (u) => u.metadata.eventId != null && u.metadata.roomId != null,
      )) {
        continue;
      }

      seenLemmas.add(construct.lemma);

      targets.add(
        AnalyticsPracticeTarget(
          target: PracticeTarget(
            tokens: [construct.id.asToken],
            exerciseType: exerciseType,
          ),
        ),
      );
    }
    return targets;
  }
}
