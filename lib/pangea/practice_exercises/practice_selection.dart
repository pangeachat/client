import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_target.dart';

class PracticeSelection {
  final Map<PracticeExerciseTypeEnum, List<PracticeTarget>>
  _practiceExerciseQueue;
  static const int maxQueueLength = 5;

  PracticeSelection(this._practiceExerciseQueue);

  List<PracticeTarget> activities(PracticeExerciseTypeEnum a) =>
      _practiceExerciseQueue[a] ?? [];

  PracticeTarget? getTarget(PracticeExerciseTypeEnum type) =>
      activities(type).firstOrNull;

  PracticeTarget? getMorphTarget(PangeaToken t, MorphFeaturesEnum morph) =>
      activities(PracticeExerciseTypeEnum.morphId).firstWhereOrNull(
        (entry) => entry.tokens.contains(t) && entry.morphFeature == morph,
      );

  Map<String, dynamic> toJson() => {
    'activityQueue': _practiceExerciseQueue.map(
      (key, value) =>
          MapEntry(key.toString(), value.map((e) => e.toJson()).toList()),
    ),
  };

  static PracticeSelection fromJson(Map<String, dynamic> json) {
    return PracticeSelection(
      (json['activityQueue'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          PracticeExerciseTypeEnum.values.firstWhere(
            (e) => e.toString() == key,
          ),
          (value as List).map((e) => PracticeTarget.fromJson(e)).toList(),
        ),
      ),
    );
  }
}
