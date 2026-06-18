import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_sessions_start_view.dart';
import 'package:fluffychat/utils/navigation_util.dart';

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
  String get descriptionText => L10n.of(context).sessionFull;

  Room? get course => widget.course;

  @override
  bool isRoleSelected(String id) => false;

  @override
  bool isRoleShimmering(String id) => false;

  @override
  bool canSelectRole(String id) => false;

  @override
  void selectRole(String id) {}

  void returnFromFullSession() {
    final course = widget.course;
    if (course != null) {
      // world_v2: switch the workspace to this course's card on the course-plan
      // tab (a token nav, not a stacked route push). See routing.instructions.md.
      context.go(
        WorkspaceNav.openCourseFilter(
          GoRouterState.of(context).uri,
          course.id,
          tab: 'course',
        ),
      );
    } else {
      NavigationUtil.goToSpaceRoute(null, [], context);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ActivitySessionStartView(widget.controller, sessionController: this);
}
