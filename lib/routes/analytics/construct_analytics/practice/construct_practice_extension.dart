import 'dart:math';

import 'package:collection/collection.dart';

import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';

extension ConstructPracticeExtension on List<ConstructUses> {
  /// Highest priority first. Scores are coarse, so many constructs tie; a
  /// shuffle before the stable sort puts tied ones in a random order, so
  /// sessions do not keep drawing the same ones (practice-exercises.
  /// instructions.md, "Standalone Practice — practice sorting").
  List<ConstructUses> practiceSort(
    PracticeExerciseTypeEnum type, {
    Random? random,
  }) {
    final sorted = List<ConstructUses>.from(this)..shuffle(random);
    mergeSort<ConstructUses>(
      sorted,
      compare: (a, b) => b
          .practiceScore(exerciseType: type)
          .compareTo(a.practiceScore(exerciseType: type)),
    );
    return sorted;
  }
}
