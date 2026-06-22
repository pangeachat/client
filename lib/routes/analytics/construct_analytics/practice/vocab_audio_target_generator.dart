import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/construct_practice_extension.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/example_message_util.dart';
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
    final Set<String> seenEventIds = {};

    final targets = <AnalyticsPracticeTarget>[];

    for (final construct in sortedConstructs) {
      if (targets.length >= AnalyticsPracticeConstants.targetsToGenerate) {
        break;
      }

      if (seenLemmas.contains(construct.lemma)) continue;

      if (construct.shouldSkipForRecentPractice(exerciseType)) {
        continue;
      }

      // Try to get an audio example message with token data for this lemma
      final exampleMessage = await ExampleMessageUtil.getAudioExampleMessage(
        construct,
        noBold: true,
      );

      if (exampleMessage == null) continue;
      final eventId = exampleMessage.eventId;
      if (eventId != null && seenEventIds.contains(eventId)) {
        continue;
      }

      seenLemmas.add(construct.lemma);
      if (eventId != null) {
        seenEventIds.add(eventId);
      }

      targets.add(
        AnalyticsPracticeTarget(
          target: PracticeTarget(
            tokens: [construct.id.asToken],
            exerciseType: exerciseType,
          ),
          audioExampleMessage: exampleMessage,
        ),
      );
    }
    return targets;
  }
}
