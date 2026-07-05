import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_preview_repo.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/room_summaries/activity_sessions_status_model.dart';
import 'package:fluffychat/features/room_summaries/activity_summary_status_enum.dart';
import 'package:fluffychat/features/room_summaries/room_summaries_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_sessions_start_view.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum NotStartedSubPage {
  main,
  join,
  view;

  List<ActivitySummaryStatus> get visibleStatuses {
    switch (this) {
      case NotStartedSubPage.join:
        return [ActivitySummaryStatus.notStarted];
      case NotStartedSubPage.view:
        return [
          ActivitySummaryStatus.inProgress,
          ActivitySummaryStatus.completed,
        ];
      case NotStartedSubPage.main:
        return [];
    }
  }
}

class NotStartedSession extends StatefulWidget {
  /// The course the activity is launched from, when there is one. Null for a
  /// standalone activity (you no longer need to be in a course to play).
  final Room? course;
  final String activityId;
  final ActivityPlanModel? activity;
  final ActivitySessionSummariesModel summaries;

  /// The open-session summaries are still being fetched (a cache miss), so the
  /// CTA should show a loading indicator rather than the join/start choice.
  final bool summariesLoading;
  final ScrollController scrollController;
  final ActivitySessionStartState controller;

  const NotStartedSession({
    super.key,
    required this.course,
    required this.activityId,
    required this.activity,
    required this.summaries,
    required this.summariesLoading,
    required this.scrollController,
    required this.controller,
  });

  @override
  NotStartedSessionController createState() => NotStartedSessionController();
}

class NotStartedSessionController extends State<NotStartedSession>
    implements ActivitySessionStateController {
  NotStartedSubPage _subPage = NotStartedSubPage.main;
  final _goalsHandler = GoalsSubscriptionHandler();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _goalsHandler.init(widget.course?.id, context, setState, () => mounted);
  }

  @override
  void dispose() {
    _goalsHandler.cancel();
    super.dispose();
  }

  NotStartedSubPage get subPage => _subPage;

  void goToJoinPage() => setState(() => _subPage = NotStartedSubPage.join);
  void goToViewPage() => setState(() => _subPage = NotStartedSubPage.view);
  void goToMainPage() => setState(() => _subPage = NotStartedSubPage.main);

  String? get joinedActivityRoomId =>
      widget.course?.activeActivityRoomId(widget.activityId);

  Room? get course => widget.course;

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
  Set<String> completedGoalIdsForRole(String id) => _goalsHandler.scan(
    id,
    Matrix.of(context).client,
    activityId: widget.activityId,
    activity: widget.activity,
  );

  @override
  bool get showRoleCards => _subPage == NotStartedSubPage.main;

  @override
  bool get showDescriptionSection => _subPage == NotStartedSubPage.main;

  @override
  List<ActivityRoleGoal>? get selectedRoleGoals => null;

  @override
  Set<String> get selectedRoleCompletedGoalIds => {};

  int get openSessionCount => widget.summaries.openSessions.length;

  bool get summariesLoading => widget.summariesLoading;

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
    // No course: the session launches standalone (the bot fills in), so no
    // extra course participants are required.
    final course = widget.course;
    if (course == null) return 0;
    final courseParticipants = await course.requestParticipants(
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
    final course = widget.course;
    // With a course, launch scoped to it; otherwise launch the activity as a
    // standalone immersive panel over the map (no course context to clear —
    // this session already has none). See routing.instructions.md.
    context.go(
      course != null
          ? WorkspaceNav.openCourseActivity(
              course.id,
              widget.activityId,
              launch: true,
            )
          : WorkspaceNav.openActivity(
              GoRouterState.of(context).uri,
              widget.activityId,
              launch: true,
              clearContext: true,
            ),
    );
  }

  void goToCourse() {
    final course = widget.course;
    if (course == null) return;
    // world_v2: token nav to the course card's course-plan tab (no stacked
    // route push). See routing.instructions.md.
    context.go(
      WorkspaceNav.openCourseFilter(
        GoRouterState.of(context).uri,
        course.id,
        tab: 'course',
      ),
    );
  }

  void inviteToCourse() {
    final course = widget.course;
    if (course == null) return;
    // world_v2: token nav to the course's invite page (no stacked route push).
    context.go(
      WorkspaceNav.openCoursePageFor(
        GoRouterState.of(context).uri,
        course.id,
        'invite',
      ),
    );
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
        await Matrix.of(context).client.joinRoom(
          roomId,
          via: widget.course?.spaceChildren
              .firstWhereOrNull((child) => child.roomId == roomId)
              ?.via,
        );

        final room = Matrix.of(context).client.getRoomById(roomId);
        if (room == null || room.membership != Membership.join) {
          await Matrix.of(context).client.waitForRoomInSync(roomId, join: true);
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
