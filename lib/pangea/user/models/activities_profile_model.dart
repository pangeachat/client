import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

class ActivitiesProfileModel {
  final List<String> bookmarkedActivities;

  ActivitiesProfileModel({
    required this.bookmarkedActivities,
  });

  static ActivitiesProfileModel get empty => ActivitiesProfileModel(
        bookmarkedActivities: [],
      );

  void addBookmark(String activityId) {
    if (!bookmarkedActivities.contains(activityId)) {
      bookmarkedActivities.add(activityId);
    }
  }

  void removeBookmark(String activityId) {
    bookmarkedActivities.remove(activityId);
  }

  static ActivitiesProfileModel fromJson(Map<String, dynamic> json) {
    if (!json.containsKey(PangeaEventTypes.profileActivities)) {
      return ActivitiesProfileModel.empty;
    }

    final profileJson = json[PangeaEventTypes.profileActivities];
    return ActivitiesProfileModel(
      bookmarkedActivities:
          List<String>.from(profileJson[ModelKey.bookmarkedActivities] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ModelKey.bookmarkedActivities: bookmarkedActivities,
    };
  }
}
