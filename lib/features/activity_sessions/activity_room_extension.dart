import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_cache.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';

extension ActivityRoomExtension on Room {
  /// The activity plan for this session room.
  ///
  /// v3 rooms store a thin `{ activity_id, version_id }` reference in
  /// `pangea.activity_plan` and the plan body stays canonical in CMS, so a
  /// reference is hydrated through [ActivityPlanCache] (async): this returns
  /// null until the plan lands, then `ActivityPlanCache` notifies its listeners
  /// to rebuild. Legacy rooms embed the full plan in state and parse inline.
  ActivityPlanModel? get activityPlan {
    final stateEvent = getState(PangeaEventTypes.activityPlan);
    if (stateEvent == null) return null;
    final content = stateEvent.content;

    // Reference shape carries no embedded plan body (no `req`); hydrate it.
    if (content[ActivitySessionConstants.activityPlanRequest] == null) {
      final referenceId = _referencePlanActivityId(content);
      if (referenceId == null) return null;
      ActivityPlanCache.instance.ensure(referenceId);
      return ActivityPlanCache.instance.cached(referenceId);
    }

    try {
      return ActivityPlanModel.fromJson(content);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"roomID": id, "stateEvent": content},
      );
      return null;
    }
  }

  /// activity_id of a reference plan: the room-type suffix
  /// (`PangeaRoomTypes.activitySession:<activity_id>`) is authoritative, with
  /// the state field as fallback. Read inline (not via [activityId]) to avoid
  /// recursion.
  String? _referencePlanActivityId(Map<String, dynamic> content) {
    if (roomType?.startsWith(PangeaRoomTypes.activitySession) == true) {
      return roomType!.split(":").last;
    }
    return content[ActivitySessionConstants.activityId] as String?;
  }

  bool get showActivityChatUI {
    // Keyed off the room type, not plan hydration, so the activity shell shows
    // immediately while the reference plan loads.
    return isActivitySession &&
        powerForChangingStateEvent(PangeaEventTypes.activityRole) == 0 &&
        powerForChangingStateEvent(PangeaEventTypes.activitySummary) == 0;
  }

  bool get isActivitySession {
    // Room type identifies a v3 session even before its reference plan is
    // hydrated; exclude only the legacy bookmark-deprecated embedded model.
    if (roomType?.startsWith(PangeaRoomTypes.activitySession) == true) {
      final plan = activityPlan;
      return plan == null || !plan.isDeprecatedModel;
    }
    final plan = activityPlan;
    return plan != null && !plan.isDeprecatedModel;
  }

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
