import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';

class PracticeSelection {
  final Map<ActivityTypeEnum, List<PracticeTarget>> _activityQueue;
  static const int maxQueueLength = 5;

  PracticeSelection(this._activityQueue);

  List<PracticeTarget> activities(ActivityTypeEnum a) =>
      _activityQueue[a] ?? [];

  PracticeTarget? getTarget(ActivityTypeEnum type) =>
      activities(type).firstOrNull;

  PracticeTarget? getMorphTarget(
    PangeaToken t,
    MorphFeaturesEnum morph,
  ) =>
      activities(ActivityTypeEnum.morphId).firstWhereOrNull(
        (entry) => entry.tokens.contains(t) && entry.morphFeature == morph,
      );

  Map<String, dynamic> toJson() => {
        'activityQueue': _activityQueue.map(
          (key, value) => MapEntry(
            key.toString(),
            value.map((e) => e.toJson()).toList(),
          ),
        ),
      };

  static PracticeSelection fromJson(Map<String, dynamic> json) {
    return PracticeSelection(
      (json['activityQueue'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          ActivityTypeEnum.values.firstWhere((e) => e.toString() == key),
          (value as List).map((e) => PracticeTarget.fromJson(e)).toList(),
        ),
      ),
    );
  }
}
