import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/example_message_util.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_constants.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';

class VocabAudioTargetGenerator {
  static Future<List<AnalyticsActivityTarget>> get(
    List<ConstructUses> constructs,
  ) async {
    // Score and sort by priority (highest first). Uses shared scorer for
    // consistent prioritization with message practice.
    constructs.sort((a, b) {
      final scoreA = a.practiceScore(activityType: ActivityTypeEnum.lemmaAudio);
      final scoreB = b.practiceScore(activityType: ActivityTypeEnum.lemmaAudio);
      return scoreB.compareTo(scoreA);
    });

    final Set<String> seenLemmas = {};
    final Set<String> seenEventIds = {};
    final targets = <AnalyticsActivityTarget>[];

    for (final construct in constructs) {
      if (targets.length >= AnalyticsPracticeConstants.targetsToGenerate) {
        break;
      }

      if (seenLemmas.contains(construct.lemma)) continue;

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
        AnalyticsActivityTarget(
          target: PracticeTarget(
            tokens: [construct.id.asToken],
            activityType: ActivityTypeEnum.lemmaAudio,
          ),
          audioExampleMessage: exampleMessage,
        ),
      );
    }
    return targets;
  }
}
