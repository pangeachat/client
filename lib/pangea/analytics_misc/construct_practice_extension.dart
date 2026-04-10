import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_type_enum.dart';

extension ConstructPracticeExtension on List<ConstructUses> {
  List<ConstructUses> practiceSort(PracticeExerciseTypeEnum type) {
    final sorted = List<ConstructUses>.from(this);
    sorted.sort((a, b) {
      final scoreA = a.practiceScore(exerciseType: type);
      final scoreB = b.practiceScore(exerciseType: type);
      return scoreB.compareTo(scoreA);
    });
    return sorted;
  }
}
