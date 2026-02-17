import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_constants.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';

class VocabMeaningTargetGenerator {
  static Future<List<AnalyticsActivityTarget>> get(
    List<ConstructUses> constructs,
  ) async {
    // Score and sort by priority (highest first). Uses shared scorer for
    // consistent prioritization with message practice.
    constructs.sort((a, b) {
      final scoreA = a.practiceScore(
        activityType: ActivityTypeEnum.lemmaMeaning,
      );
      final scoreB = b.practiceScore(
        activityType: ActivityTypeEnum.lemmaMeaning,
      );
      return scoreB.compareTo(scoreA);
    });

    final Set<String> seenLemmas = {};
    final targets = <AnalyticsActivityTarget>[];
    for (final construct in constructs) {
      if (seenLemmas.contains(construct.lemma)) continue;
      seenLemmas.add(construct.lemma);
      targets.add(
        AnalyticsActivityTarget(
          target: PracticeTarget(
            tokens: [construct.id.asToken],
            activityType: ActivityTypeEnum.lemmaMeaning,
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
