import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_start_page.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_state_controller.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_sessions_start_view.dart';
import 'package:fluffychat/pangea/navigation/navigation_util.dart';

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
    with ActivitySessionStateController {
  @override
  String get descriptionText => L10n.of(context).sessionFull;

  Room? get course => widget.course;

  void returnFromFullSession() {
    final course = widget.course;
    if (course != null) {
      context.push("/rooms/spaces/${course.id}/details?tab=course");
    } else {
      NavigationUtil.goToSpaceRoute(null, [], context);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ActivitySessionStartView(widget.controller, sessionController: this);
}
