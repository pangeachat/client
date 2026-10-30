import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_preview_repo.dart';
import 'package:fluffychat/features/activity_sessions/play_with_bot_intent.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/room_summaries/activity_sessions_status_model.dart';
import 'package:fluffychat/features/room_summaries/activity_summary_status_enum.dart';
import 'package:fluffychat/features/room_summaries/room_summaries_model.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_sessions_start_view.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/chat/activity_sessions/session_presence_tracker.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum NotStartedSubPage {
  /// The activity itself, listing any open sessions under it.
  main,

  /// The Completed list.
  view;

  List<ActivitySummaryStatus> get visibleStatuses {
    switch (this) {
      case NotStartedSubPage.view:
        return [ActivitySummaryStatus.completed];
      case NotStartedSubPage.main:
        return [ActivitySummaryStatus.notStarted];
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

  /// The learner's saved sessions of this activity outside [course] — in
  /// another course or none — which the finished view lists under "Other
  /// courses" (#9559).
  final Map<String, RoomSummaryResponse> otherCompletedSessions;

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
    this.otherCompletedSessions = const {},
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
  bool _openedJoinedSession = false;

  @override
  void initState() {
    super.initState();
    // The client is read through context, which isn't available yet.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openJoinedSessionIfFull(),
    );
  }

  @override
  void didUpdateWidget(NotStartedSession oldWidget) {
    super.didUpdateWidget(oldWidget);
    _openJoinedSessionIfFull();
  }

  /// Opening an activity whose session the learner is in and is full goes
  /// straight into its chat (activity-start-page.instructions.md, "The CTA
  /// row").
  void _openJoinedSessionIfFull() {
    if (_openedJoinedSession || !mounted) return;
    final roomId = joinedActivityRoomId;
    if (roomId == null) return;
    final room = Matrix.of(context).client.getRoomById(roomId);
    if (room == null || !room.isActivityStarted) return;
    _openedJoinedSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) goToJoinedActivity();
    });
  }

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

  // The sub-page change is reported to the start state because the open
  // sessions mounting is a tutorial trigger it can't otherwise see
  // (ActivitySessionStartState.onTutorialSurfaceChanged).
  void goToViewPage() => _setSubPage(NotStartedSubPage.view);
  void goToMainPage() => _setSubPage(NotStartedSubPage.main);

  void goBackFromSubPage() => goToMainPage();

  void _setSubPage(NotStartedSubPage subPage) {
    setState(() => _subPage = subPage);
    widget.controller.onTutorialSurfaceChanged();
  }

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

  bool get isCourseAdmin => widget.course?.isRoomAdmin == true;

  String? get _ownUserId => Matrix.of(context).client.userID;

  Map<String, RoomSummaryResponse> get _completedSessions =>
      activityStatuses.getSessionsByStatus(ActivitySummaryStatus.completed);

  /// The completed sessions the Completed subpage lists for this viewer. A course admin oversees
  /// the whole course, so they see every finished session with their own floated
  /// to the top; everyone else — including anyone on a standalone activity,
  /// which has no course to administer — sees only the sessions they personally
  /// finished (their role archived, [RoomSummaryResponse.isCompleteByUserId], so
  /// one others wrapped up after they left doesn't read as theirs).
  Map<String, RoomSummaryResponse> get visibleCompletedSessions {
    final userId = _ownUserId;
    if (!isCourseAdmin) {
      if (userId == null) return {};
      return Map.fromEntries(
        _completedSessions.entries.where(
          (e) => e.value.isCompleteByUserId(userId),
        ),
      );
    }
    final entries = _completedSessions.entries.toList();
    if (userId != null) {
      entries.sort((a, b) {
        final aOwn = a.value.isCompleteByUserId(userId) ? 0 : 1;
        final bOwn = b.value.isCompleteByUserId(userId) ? 0 : 1;
        return aOwn.compareTo(bOwn);
      });
    }
    return Map.fromEntries(entries);
  }

  /// The learner's saved sessions of this activity outside the course in
  /// context, listed after this course's under "Other courses" (#9559).
  Map<String, RoomSummaryResponse> get otherCompletedSessions =>
      widget.otherCompletedSessions;

  /// Whether [visibleCompletedSessions] or [otherCompletedSessions] has anything — tested cheaply (no build
  /// or sort of the collection) since it gates several CTAs on every rebuild.
  bool get hasCompletedSessions {
    if (otherCompletedSessions.isNotEmpty) return true;
    if (isCourseAdmin) return _completedSessions.isNotEmpty;
    final userId = _ownUserId;
    return userId != null &&
        _completedSessions.values.any((s) => s.isCompleteByUserId(userId));
  }

  Future<int> get neededCourseParticipants async {
    // No course: the session launches standalone (the bot fills in), so no
    // extra course participants are required.
    final course = widget.course;
    if (course == null) return 0;
    final availableParticipants = await course.availableActivityParticipants();
    final numParticipants = widget.activity?.req.numberOfParticipants ?? 0;
    if (availableParticipants >= numParticipants) return 0;
    return numParticipants - availableParticipants;
  }

  void goToJoinedActivity() {
    if (joinedActivityRoomId == null) return;
    NavigationUtil.goToSpaceRoute(joinedActivityRoomId!, [], context);
  }

  /// A two-seat activity offers "Play with others" beside "Play with Pangea
  /// Bot"; larger ones need people, so they offer a single Start.
  bool get offersBot => (widget.activity?.req.numberOfParticipants ?? 0) == 2;

  /// Pick a role, then the session launches with the bot already added.
  void playWithBot() => startNewActivity(withBot: true);

  /// Open sessions "Play with others" tries before opening a new one.
  static const int _maxJoinAttempts = 3;

  /// Joins an open session, read fresh at the tap, trying the next one when a
  /// seat is gone on arrival. It gives up after [_maxJoinAttempts] tries, or
  /// when none is left, and starts a new session even if more are open.
  /// A failed read shows its error and joins nothing. See
  /// activity-start-page.instructions.md, "Open sessions".
  Future<void> playWithHuman() async {
    final resp = await showFutureLoadingDialog<({String roomId, bool seated})?>(
      context: context,
      future: () async {
        final tried = <String>{};
        for (var attempt = 0; attempt < _maxJoinAttempts; attempt++) {
          final fresh = await widget.controller.refreshSummaries();
          if (!mounted) return null;
          final roomId = await bestOpenSessionId(fresh, exclude: tried);
          if (roomId == null) return null;
          final outcome = await _joinAndClaimSeat(roomId);
          switch (outcome) {
            case _SeatOutcome.seated:
              return (roomId: roomId, seated: true);
            case _SeatOutcome.picksRole:
              return (roomId: roomId, seated: false);
            case _SeatOutcome.noSeat:
              tried.add(roomId);
              await _leaveWithoutSeat(roomId);
          }
        }
        return null;
      },
    );
    if (resp.isError || !mounted) return;
    final joined = resp.result;
    if (joined == null) {
      startNewActivity();
      return;
    }
    await ActivitySessionPreviewRepo.set(joined.roomId);
    if (!mounted) return;
    if (joined.seated) {
      NavigationUtil.goToSpaceRoute(joined.roomId, [], context);
    } else {
      _viewSession(joined.roomId);
    }
  }

  /// The open session in [summaries] to join, skipping [exclude]: a course
  /// ping's, else the most recently active (the list's top). Uses only
  /// presence the client already holds, so the tap doesn't wait on a request.
  Future<String?> bestOpenSessionId(
    ActivitySessionSummariesModel summaries, {
    Set<String> exclude = const {},
  }) async {
    final open = {
      for (final entry
          in summaries.activitySessionStatuses
              .getSessionsByStatus(ActivitySummaryStatus.notStarted)
              .entries)
        if (!exclude.contains(entry.key)) entry.key: entry.value,
    };
    if (open.isEmpty) return null;
    final ping = CoursePingBadgeCache.instance.value;
    if (ping != null &&
        ping.courseId == widget.course?.id &&
        ping.activityId == widget.activityId &&
        open.containsKey(ping.sessionRoomId)) {
      return ping.sessionRoomId;
    }
    final presence = SessionPresenceTracker(Matrix.of(context).client);
    try {
      await presence.watch([
        for (final summary in open.values) ...summary.joinedMemberIds,
      ], cachedOnly: true);
      final now = DateTime.now();
      final entries = open.entries.toList()
        ..sort((a, b) {
          final byRecent = SessionPresenceTracker.compareRecentFirst(
            presence.lastActiveOf(a.value.joinedMemberIds, now: now),
            presence.lastActiveOf(b.value.joinedMemberIds, now: now),
          );
          return byRecent != 0 ? byRecent : a.key.compareTo(b.key);
        });
      return entries.first.key;
    } finally {
      presence.dispose();
    }
  }

  /// Every start says whether the bot comes along, so an earlier "Play with
  /// Pangea Bot" that was backed out of can't carry into a later start.
  void startNewActivity({bool withBot = false}) {
    PlayWithBotIntent.set(widget.activityId, withBot: withBot);
    //Nothing to jump to if container is minimized, so skip
    if (widget.scrollController.hasClients) widget.scrollController.jumpTo(0);
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
            ),
    );
  }

  void goToCourse() {
    final course = widget.course;
    if (course == null) return;
    // world_v2: token nav to the course card (no stacked route push). No
    // section param — it would scroll the page on open (#8357); the course
    // plan already leads the page. See routing.instructions.md.
    context.go(
      WorkspaceNav.openCourse(GoRouterState.of(context).uri, course.id),
    );
  }

  /// Inviting to the course is power-gated. A learner without invite rights can
  /// only fail on the invite page, so the CTA isn't offered to them (#7875).
  bool get canInviteToCourse => widget.course?.canInvite == true;

  void inviteToCourse() {
    final course = widget.course;
    if (course == null || !course.canInvite) return;
    // world_v2: token nav to the course's invite page (no stacked route push).
    context.go(
      WorkspaceNav.openCoursePageFor(
        GoRouterState.of(context).uri,
        course.id,
        RoomSubpageEnum.invite,
      ),
    );
  }

  /// Show a session from the join list inside this activity's panel, so its
  /// close is a back arrow to the list.
  void _viewSession(String roomId) => context.go(
    WorkspaceNav.openActivitySession(
      GoRouterState.of(context).uri,
      widget.activityId,
      roomId,
    ),
  );

  /// Joins [roomId], tapped in the open sessions list: into the chat when its
  /// one open seat is claimed, else to the session's page. The learner chose
  /// this session, so a lost seat doesn't move them to another.
  Future<void> joinActivityByRoomId(String roomId) async {
    final resp = await showFutureLoadingDialog(
      context: context,
      future: () => _joinAndClaimSeat(roomId),
    );
    if (resp.isError) return;
    await ActivitySessionPreviewRepo.set(roomId);
    if (!mounted) return;
    if (resp.result == _SeatOutcome.seated) {
      NavigationUtil.goToSpaceRoute(roomId, [], context);
    } else {
      _viewSession(roomId);
    }
  }

  /// Joins [roomId] if the learner isn't in it yet, then claims its seat when
  /// exactly one is open.
  Future<_SeatOutcome> _joinAndClaimSeat(String roomId) async {
    final client = Matrix.of(context).client;
    final existing = client.getRoomById(roomId);
    if (existing == null || existing.membership != Membership.join) {
      await client.joinRoom(
        roomId,
        via: widget.course?.spaceChildren
            .firstWhereOrNull((child) => child.roomId == roomId)
            ?.via,
      );
      final joined = client.getRoomById(roomId);
      if (joined == null || joined.membership != Membership.join) {
        await client.waitForRoomInSync(roomId, join: true);
      }
    }
    return _claimOnlyOpenRole(client.getRoomById(roomId));
  }

  /// Leaves a session whose seat was gone, so the learner isn't left a member.
  Future<void> _leaveWithoutSeat(String roomId) async {
    final room = Matrix.of(context).client.getRoomById(roomId);
    if (room == null || room.membership != Membership.join) return;
    try {
      await room.leave();
    } catch (e, s) {
      // silent-ok: the next session is still worth trying; logged.
      ErrorHandler.logError(e: e, s: s, data: {'roomId': roomId});
    }
  }

  /// Claims [room]'s seat when exactly one is open.
  Future<_SeatOutcome> _claimOnlyOpenRole(Room? room) async {
    final activity = widget.activity;
    if (room == null || activity == null) return _SeatOutcome.noSeat;
    if (room.hasPickedRole) return _SeatOutcome.seated;
    // Seat math needs each holder's membership (left holders free a seat).
    await room.requestParticipants(
      const [Membership.join, Membership.invite, Membership.knock],
      false,
      true,
    );
    final taken = room.assignedRoles?.keys.toSet() ?? const <String>{};
    final open = [
      for (final role in activity.roles.values)
        if (!taken.contains(role.id)) role,
    ];
    if (open.isEmpty) return _SeatOutcome.noSeat;
    if (open.length > 1) return _SeatOutcome.picksRole;
    try {
      await room.joinActivity(open.single);
    } on RoleException {
      // silent-ok: someone took the seat first; the caller decides what next.
      return _SeatOutcome.noSeat;
    }
    // The claim rewrites the whole roles state, so a simultaneous claim can
    // silently overwrite it; reading it back catches that.
    return await _stillHoldsSeat(room, open.single.id)
        ? _SeatOutcome.seated
        : _SeatOutcome.noSeat;
  }

  Future<bool> _stillHoldsSeat(Room room, String roleId) async {
    try {
      final content = await room.client.getRoomStateWithKey(
        room.id,
        PangeaEventTypes.activityRole,
        '',
      );
      final holder = ActivityRolesModel.fromJson(content).roles[roleId];
      return holder?.userId == room.client.userID;
    } catch (e, s) {
      // silent-ok: the claim succeeded; an unreadable check keeps the seat.
      ErrorHandler.logError(e: e, s: s, data: {'roomId': room.id});
      return true;
    }
  }

  @override
  Widget build(BuildContext context) =>
      ActivitySessionStartView(widget.controller, sessionController: this);
}

/// Where a learner stands in a session after trying for its seat.
enum _SeatOutcome {
  /// They hold a role and can go into the session.
  seated,

  /// Several roles are open, so they choose one from the session's page.
  picksRole,

  /// No seat was left for them.
  noSeat,
}
