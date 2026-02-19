import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';

extension ConstructPracticeExtension on List<ConstructUses> {
  List<ConstructUses> practiceSort(ActivityTypeEnum type) {
    final sorted = List<ConstructUses>.from(this);
    sorted.sort((a, b) {
      final scoreA = a.practiceScore(activityType: type);
      final scoreB = b.practiceScore(activityType: type);
      return scoreB.compareTo(scoreA);
    });
    return sorted;
  }
}
