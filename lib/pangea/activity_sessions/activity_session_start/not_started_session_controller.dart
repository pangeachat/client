import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_preview/activity_session_preview_repo.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_start_page.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_state_controller.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_sessions_start_view.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/navigation/navigation_util.dart';
import 'package:fluffychat/pangea/room_summaries/activity_sessions_status_model.dart';
import 'package:fluffychat/pangea/room_summaries/activity_summary_status_enum.dart';
import 'package:fluffychat/pangea/room_summaries/room_summaries_model.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum NotStartedSubPage { main, join, view }

class NotStartedSession extends StatefulWidget {
  final Room course;
  final String activityId;
  final ActivityPlanModel? activity;
  final ActivitySessionSummariesModel summaries;
  final ScrollController scrollController;
  final ActivitySessionStartState controller;

  const NotStartedSession({
    super.key,
    required this.course,
    required this.activityId,
    required this.activity,
    required this.summaries,
    required this.scrollController,
    required this.controller,
  });

  @override
  NotStartedSessionController createState() => NotStartedSessionController();
}

class NotStartedSessionController extends State<NotStartedSession>
    implements ActivitySessionStateController {
  NotStartedSubPage _subPage = NotStartedSubPage.main;
  Map<String, Set<String>> _completedGoalIdsCache = {};
  StreamSubscription? _roomStateSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _roomStateSubscription ??= Matrix.of(context).client.onRoomState.stream
        .listen((_) {
          if (mounted) {
            setState(() => _completedGoalIdsCache = {});
          }
        });
  }

  @override
  void dispose() {
    _roomStateSubscription?.cancel();
    super.dispose();
  }

  NotStartedSubPage get subPage => _subPage;

  void goToJoinPage() => setState(() => _subPage = NotStartedSubPage.join);
  void goToViewPage() => setState(() => _subPage = NotStartedSubPage.view);
  void goToMainPage() => setState(() => _subPage = NotStartedSubPage.main);

  String? get joinedActivityRoomId =>
      widget.course.activeActivityRoomId(widget.activityId);

  Room get course => widget.course;

  @override
  String? get descriptionText =>
      joinedActivityRoomId != null ? L10n.of(context).inOngoingActivity : null;

  @override
  bool isRoleSelected(String id) => false;

  @override
  bool isRoleShimmering(String id) => false;

  @override
  bool canSelectRole(String id) => false;

  @override
  void selectRole(String id) {}

  @override
  bool showStarsCard(String id) => true;

  @override
  double get roleCardOpacity => 0.7;

  @override
  bool get goalsStartCollapsed => false;

  @override
  Set<String> completedGoalIdsForRole(String id) {
    if (_completedGoalIdsCache.containsKey(id)) {
      return _completedGoalIdsCache[id]!;
    }
    return _completedGoalIdsCache[id] =
        ActivitySessionStateController.scanCompletedGoalIds(
          activityId: widget.activityId,
          activity: widget.activity,
          roleId: id,
          rooms: Matrix.of(context).client.rooms,
        );
  }

  @override
  bool get showRoleCards => _subPage == NotStartedSubPage.main;

  @override
  bool get showDescriptionSection => _subPage == NotStartedSubPage.main;

  @override
  List<ActivityRoleGoal>? get selectedRoleGoals => null;

  @override
  Set<String> get selectedRoleCompletedGoalIds => {};

  int get openSessionCount => widget.summaries.openSessions.length;

  ActivitySessionsStatusModel get activityStatuses =>
      widget.summaries.activitySessionStatuses;

  bool get hasCurrentOrFinishedSessions =>
      activityStatuses
          .getSessionsByStatus(ActivitySummaryStatus.inProgress)
          .isNotEmpty ||
      activityStatuses
          .getSessionsByStatus(ActivitySummaryStatus.completed)
          .isNotEmpty;

  int get currentOrFinishedSessionCount =>
      activityStatuses
          .getSessionsByStatus(ActivitySummaryStatus.inProgress)
          .length +
      activityStatuses
          .getSessionsByStatus(ActivitySummaryStatus.completed)
          .length;

  Future<int> get neededCourseParticipants async {
    final courseParticipants = await widget.course.requestParticipants(
      const [Membership.join, Membership.invite, Membership.knock],
      false,
      true,
    );

    final botInCourse = courseParticipants.any(
      (p) => p.id == BotName.byEnvironment,
    );

    final addBotToAvailableUsers = !botInCourse;
    final numParticipants = widget.activity?.req.numberOfParticipants ?? 0;
    final availableParticipants =
        courseParticipants.length + (addBotToAvailableUsers ? 1 : 0);

    if (availableParticipants >= numParticipants) return 0;
    return numParticipants - availableParticipants;
  }

  void goToJoinedActivity() {
    if (joinedActivityRoomId == null) return;
    NavigationUtil.goToSpaceRoute(joinedActivityRoomId!, [], context);
  }

  void startNewActivity() {
    widget.scrollController.jumpTo(0);
    context.go(
      "/rooms/spaces/${widget.course.id}/activity/${widget.activityId}?launch=true",
    );
  }

  void goToCourse() {
    context.push("/rooms/spaces/${widget.course.id}/details?tab=course");
  }

  void inviteToCourse() {
    context.push("/rooms/spaces/${widget.course.id}/invite");
  }

  Future<void> joinActivityByRoomId(String roomId) async {
    final room = Matrix.of(context).client.getRoomById(roomId);
    if (room != null && room.membership == Membership.join) {
      NavigationUtil.goToSpaceRoute(roomId, [], context);
      return;
    }

    final resp = await showFutureLoadingDialog(
      context: context,
      future: () async {
        await widget.course.client.joinRoom(
          roomId,
          via: widget.course.spaceChildren
              .firstWhereOrNull((child) => child.roomId == roomId)
              ?.via,
        );

        final room = widget.course.client.getRoomById(roomId);
        if (room == null || room.membership != Membership.join) {
          await widget.course.client.waitForRoomInSync(roomId, join: true);
        }
      },
    );

    if (!resp.isError) {
      await ActivitySessionPreviewRepo.set(roomId);
      NavigationUtil.goToSpaceRoute(roomId, [], context);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ActivitySessionStartView(widget.controller, sessionController: this);
}
