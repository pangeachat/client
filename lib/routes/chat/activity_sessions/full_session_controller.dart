import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_sessions_start_view.dart';
import 'package:fluffychat/routes/chat_list/chat_invite_dialog.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class FullSession extends StatefulWidget {
  final Room? course;
  final ActivitySessionStartState controller;
  const FullSession({
    super.key,
    required this.course,
    required this.controller,
  });

  @override
  FullSessionController createState() => FullSessionController();
}

class FullSessionController extends State<FullSession>
    implements ActivitySessionStateController {
  @override
  String get descriptionText => widget.controller.invitedSessionFinished
      ? L10n.of(context).sessionFinished
      : L10n.of(context).sessionFull;

  Room? get course => widget.course;

  bool get isInvited => widget.controller.invitedRoom != null;

  @override
  bool isRoleSelected(String id) => false;

  @override
  bool isRoleShimmering(String id) => false;

  @override
  bool canSelectRole(String id) => false;

  @override
  void selectRole(String id) {}

  @override
  bool showStarsCard(String id) => false;

  @override
  double get roleCardOpacity => 1.0;

  @override
  bool get goalsStartCollapsed => false;

  @override
  bool get showRoleCards => true;

  @override
  bool get showDescriptionSection => true;

  @override
  Set<String> completedGoalIdsForRole(String id) => {};

  @override
  List<ActivityRoleGoal>? get selectedRoleGoals => null;

  @override
  Set<String> get selectedRoleCompletedGoalIds => {};

  /// Declines the invite, and leaves the way the return button would.
  Future<void> dismissInvite() async {
    final room = widget.controller.invitedRoom;
    if (room == null) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: room.leave,
    );
    if (result.isError) return;
    returnFromFullSession();
  }

  /// Accepts the invite, for someone invited on purpose to see the session.
  Future<void> openInvitedChat() async {
    final room = widget.controller.invitedRoom;
    if (room == null) return;
    final page = widget.controller;
    if (await ChatInviteDialog.join(context, room) && page.mounted) {
      NavigationUtil.goToSpaceRoute(room.id, [], page.context);
    }
  }

  void returnFromFullSession() {
    // The page's context: an answered invite can swap this view out when it
    // syncs, and the page outlives the swap.
    final page = widget.controller;
    if (!page.mounted) return;
    final context = page.context;
    final course = widget.course;
    if (course != null) {
      // world_v2: switch the workspace to this course's card (a token nav,
      // not a stacked route push). No section param — it would scroll the
      // page on open (#8357); the course plan already leads the page. See
      // routing.instructions.md.
      context.go(
        WorkspaceNav.openCourse(GoRouterState.of(context).uri, course.id),
      );
    } else {
      NavigationUtil.goToSpaceRoute(null, [], context);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ActivitySessionStartView(widget.controller, sessionController: this);
}
