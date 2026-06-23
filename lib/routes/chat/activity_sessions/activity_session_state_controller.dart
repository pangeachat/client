import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_client_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';

abstract class ActivitySessionStateController {
  String? get descriptionText;

  bool isRoleSelected(String id);

  bool isRoleShimmering(String id);

  bool canSelectRole(String id);

  void selectRole(String id);

  bool showStarsCard(String id);

  double get roleCardOpacity;

  bool get goalsStartCollapsed;

  bool get showRoleCards;

  bool get showDescriptionSection;

  Set<String> completedGoalIdsForRole(String id);

  List<ActivityRoleGoal>? get selectedRoleGoals;

  Set<String> get selectedRoleCompletedGoalIds;
}

class GoalsSubscriptionHandler {
  final Map<String, Set<String>> _cache = {};
  StreamSubscription? _subscription;

  void init(
    String? roomId,
    BuildContext context,
    StateSetter setState,
    bool Function() isMounted,
  ) {
    _subscription ??= Matrix.of(context).client.onRoomState.stream
        .where(
          (u) =>
              u.roomId == roomId &&
              u.state.type == PangeaEventTypes.orchestratorAwardedGoals,
        )
        .listen((_) {
          if (isMounted()) setState(() => _cache.clear());
        });
  }

  void cancel() => _subscription?.cancel();

  void clearCache() => _cache.clear();

  Set<String> scan(
    String id,
    Client client, {
    required String? activityId,
    required ActivityPlanModel? activity,
  }) {
    if (_cache.containsKey(id)) return _cache[id]!;
    return _cache[id] = client.scanCompletedGoalIds(
      activityId: activityId,
      activity: activity,
      roleId: id,
    );
  }
}
