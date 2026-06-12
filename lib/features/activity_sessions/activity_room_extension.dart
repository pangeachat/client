import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';

extension ActivityRoomExtension on Room {
  ActivityPlanModel? get activityPlan {
    final stateEvent = getState(PangeaEventTypes.activityPlan);
    if (stateEvent == null) return null;

    try {
      return ActivityPlanModel.fromJson(stateEvent.content);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"roomID": id, "stateEvent": stateEvent.content},
      );
      return null;
    }
  }

  bool get showActivityChatUI {
    return activityPlan != null &&
        powerForChangingStateEvent(PangeaEventTypes.activityRole) == 0 &&
        powerForChangingStateEvent(PangeaEventTypes.activitySummary) == 0;
  }

  bool get isActivitySession =>
      (roomType?.startsWith(PangeaRoomTypes.activitySession) == true ||
          activityPlan != null) &&
      activityPlan?.isDeprecatedModel == false &&
      activityPlan?.activityId != null;

  String? get activityId {
    if (!isActivitySession) return null;
    if (roomType?.startsWith(PangeaRoomTypes.activitySession) == true) {
      return roomType!.split(":").last;
    }
    return activityPlan?.activityId;
  }

  Room? get courseParent => pangeaSpaceParents.firstWhereOrNull(
    (parent) => parent.coursePlan != null,
  );
}
