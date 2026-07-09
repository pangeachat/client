import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_sessions_start_view.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Read-only session page for an activity the backend no longer has — the
/// removed-activity fallback ladder in activities.instructions.md. With a plan
/// recovered from legacy room state the page renders fully (roles, goal
/// labels, media); with none the view falls back to the archived body built
/// from role/goal room state. Either way nothing can be joined, selected, or
/// written — the CTA footer shows only the "no longer supported" notice.
class ArchivedSession extends StatefulWidget {
  final Room? room;
  final ActivityPlanModel? activity;
  final ActivitySessionStartState controller;

  const ArchivedSession({
    super.key,
    required this.room,
    required this.activity,
    required this.controller,
  });

  @override
  ArchivedSessionController createState() => ArchivedSessionController();
}

class ArchivedSessionController extends State<ArchivedSession>
    implements ActivitySessionStateController {
  final _goalsHandler = GoalsSubscriptionHandler();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _goalsHandler.init(widget.room?.id, context, setState, () => mounted);
  }

  @override
  void dispose() {
    _goalsHandler.cancel();
    super.dispose();
  }

  @override
  String get descriptionText => L10n.of(context).activityNoLongerSupported;

  @override
  bool get goalsStartCollapsed => true;

  @override
  List<ActivityRoleGoal>? get selectedRoleGoals {
    final roleId = widget.room?.ownRoleState?.id;
    if (roleId == null) return null;
    return widget.activity?.roles[roleId]?.allGoals;
  }

  @override
  Set<String> get selectedRoleCompletedGoalIds {
    final roleId = widget.room?.ownRoleState?.id;
    if (roleId == null) return {};
    return completedGoalIdsForRole(roleId);
  }

  @override
  Set<String> completedGoalIdsForRole(String id) => _goalsHandler.scan(
    id,
    Matrix.of(context).client,
    activityId: widget.controller.widget.activityId,
    activity: widget.activity,
  );

  @override
  bool isRoleSelected(String id) => widget.room?.ownRoleState?.id == id;

  @override
  bool isRoleShimmering(String id) => false;

  @override
  bool canSelectRole(String id) => false;

  @override
  void selectRole(String id) {}

  /// Earned-star progress shows on every role card — reviewing past progress
  /// is the point of the archived view.
  @override
  bool showStarsCard(String id) => widget.room != null;

  @override
  double get roleCardOpacity => 1.0;

  @override
  bool get showRoleCards => widget.activity != null;

  @override
  bool get showDescriptionSection => widget.activity != null;

  @override
  Widget build(BuildContext context) =>
      ActivitySessionStartView(widget.controller, sessionController: this);
}
