import 'dart:math';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_planner/activity_role_model.dart';
import 'package:fluffychat/pangea/activity_planner/bookmarked_activities_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

extension ActivityRoomExtension on Room {
  Future<void> sendActivityPlan(
    ActivityPlanModel activity, {
    Uint8List? avatar,
    String? filename,
  }) async {
    BookmarkedActivitiesRepo.save(activity);

    if (canChangeStateEvent(PangeaEventTypes.activityPlan)) {
      await client.setRoomStateWithKey(
        id,
        PangeaEventTypes.activityPlan,
        "",
        activity.toJson(),
      );
    }
  }

  Future<void> setActivityRole(
    String userId, {
    String? role,
  }) async {
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activityRole,
      userId,
      ActivityRoleModel(
        userId: userId,
        role: role,
      ).toJson(),
    );
  }

  ActivityPlanModel? get activityPlan {
    final stateEvent = getState(PangeaEventTypes.activityPlan);
    if (stateEvent == null) return null;

    try {
      return ActivityPlanModel.fromJson(stateEvent.content);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "roomID": id,
          "stateEvent": stateEvent.content,
        },
      );
      return null;
    }
  }

  ActivityRoleModel? activityRole(String userId) {
    final stateEvent = getState(PangeaEventTypes.activityRole, userId);
    if (stateEvent == null) return null;

    try {
      return ActivityRoleModel.fromJson(stateEvent.content);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "roomID": id,
          "userId": userId,
          "stateEvent": stateEvent.content,
        },
      );
      return null;
    }
  }

  List<ActivityRoleModel> get activityRoles {
    final roles = states[PangeaEventTypes.activityRole]?.values.toList() ?? [];
    return roles.map((r) => ActivityRoleModel.fromJson(r.content)).toList();
  }

  bool get hasJoinedActivity {
    return activityPlan == null || activityRole(client.userID!) != null;
  }

  int? get numberOfParticipants {
    return activityPlan?.req.numberOfParticipants;
  }

  int get remainingRoles {
    if (numberOfParticipants == null) return 0;
    return max(0, numberOfParticipants! - activityRoles.length);
  }
}
