// ignore_for_file: depend_on_referenced_packages

//import 'package:get_storage/get_storage.dart';
import 'package:uuid/uuid.dart';

import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/spaces/constants/space_constants.dart';

class BookmarkedActivitiesRepo {
  static const Uuid _uuid = Uuid();

  /// save an activity to the list of bookmarked activities
  /// returns the activity with a bookmarkId
  static Future<ActivityPlanModel> save(ActivityPlanModel activity) async {
    activity.bookmarkId ??= _uuid.v4();

    await Storage.bookStorage.write(
      activity.bookmarkId!,
      activity.toJson(),
    );

    //now it has a bookmarkId
    return activity;
  }

  static Future<void> remove(String bookmarkId) => Storage.bookStorage.remove(bookmarkId);

  static bool isBookmarked(ActivityPlanModel activity) {
    return activity.bookmarkId != null &&
        Storage.bookStorage.read(activity.bookmarkId!) != null;
  }

  static List<ActivityPlanModel> get() {
    final list = Storage.bookStorage.getValues();

    if (list == null) return [];

    return (list as Iterable)
        .map((json) => ActivityPlanModel.fromJson(json))
        .toList();
  }
}
