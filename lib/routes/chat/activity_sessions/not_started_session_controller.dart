import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_preview_repo.dart';
import 'package:fluffychat/features/activity_sessions/play_with_bot_intent.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/activity_lock_client_extension.dart';
import 'package:fluffychat/features/room_summaries/activity_sessions_status_model.dart';
import 'package:fluffychat/features/room_summaries/activity_summary_status_enum.dart';
import 'package:fluffychat/features/room_summaries/room_summaries_model.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/named_timeout.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_sessions_start_view.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/utils/stream_extension.dart';
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
        return [ActivitySummaryStatus.completed];
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

  /// The courses whose progression locks starting a new session; joining an
  /// open one never is. Null until the first check lands — the start buttons
  /// wait for it rather than flashing and vanishing.
  List<Room>? _lockingCourses;
  List<Room> get lockingCourses => _lockingCourses ?? const [];
  bool get isLocked => lockingCourses.isNotEmpty;
  bool get lockResolved => _lockingCourses != null;

  /// Bumped per check, so an older check that finishes late is dropped.
  int _lockCheck = 0;

  /// The join list was opened for the learner because the activity had open
  /// sessions, rather than by a tap.
  bool _landedOnJoinList = false;

  /// Stars and teacher flags are room state, so a sync can change the lock
  /// while the page is open; only syncs carrying them re-check.
  StreamSubscription? _lockRefreshSub;

  @override
  void initState() {
    super.initState();
    _resolveLock();
    _lockRefreshSub = Matrix.of(context).client.onSync.stream
        .where(ActivityLockClientExtension.syncAffectsLocks)
        .rateLimit(const Duration(seconds: 2))
        .listen((_) => _resolveLock());
    _syncJoinListLanding();
  }

  @override
  void didUpdateWidget(NotStartedSession oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course?.id != widget.course?.id) _resolveLock();
    _syncJoinListLanding();
  }

  /// A joinable activity opens straight on its join list, so an open session
  /// is never passed over for a bot the learner didn't need; if its last open
  /// session fills while they look, the page falls back to the start choice.
  void _syncJoinListLanding() {
    if (widget.summariesLoading || joinedActivityRoomId != null) return;
    final hasOpen = openSessionCount > 0;
    if (hasOpen && _subPage == NotStartedSubPage.main && !_landedOnJoinList) {
      _landedOnJoinList = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) goToJoinPage();
      });
    } else if (!hasOpen && _subPage == NotStartedSubPage.join) {
      _landedOnJoinList = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) goToMainPage();
      });
    }
  }

  /// How long the start buttons wait on a lock check before giving up on it.
  static const Duration _lockCheckLimit = Duration(seconds: 10);

  Future<void> _resolveLock() async {
    final check = ++_lockCheck;
    List<Room> courses;
    try {
      courses = await Matrix.of(context).client
          .coursesLockingActivity(
            widget.activityId,
            courseId: widget.course?.id,
          )
          .timeoutNamed(_lockCheckLimit, 'lock check: activity start page');
    } catch (e, s) {
      // A failed or stuck check must not hold the start buttons on their
      // loading bar: fail open, as the resolver does before progress loads.
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'activityId': widget.activityId},
        level: SentryLevel.warning,
      );
      courses = const [];
    }
    if (!mounted || check != _lockCheck) return;
    final previous = _lockingCourses;
    final unchanged =
        previous != null &&
        previous.map((r) => r.id).join() == courses.map((r) => r.id).join();
    if (!unchanged) setState(() => _lockingCourses = courses);
  }

  /// Open [course] on its course plan, where the learner's current Mission
  /// is — the way to unlock this activity.
  void goToLockingCourse(Room course) => context.go(
    WorkspaceNav.openCourse(
      GoRouterState.of(context).uri,
      course.id,
      tab: SpaceSettingsTabs.course,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _goalsHandler.init(widget.course?.id, context, setState, () => mounted);
  }

  @override
  void dispose() {
    _lockRefreshSub?.cancel();
    _goalsHandler.cancel();
    super.dispose();
  }

  NotStartedSubPage get subPage => _subPage;

  // The sub-page change is reported to the start state because the join list
  // mounting is a tutorial trigger it can't otherwise see
  // (ActivitySessionStartState.onTutorialSurfaceChanged).
  void goToJoinPage() => _setSubPage(NotStartedSubPage.join);
  void goToViewPage() => _setSubPage(NotStartedSubPage.view);
  void goToMainPage() => _setSubPage(NotStartedSubPage.main);

  /// Back from the Completed list returns to the join list when that is where
  /// the activity landed.
  void goBackFromSubPage() => _setSubPage(
    _landedOnJoinList ? NotStartedSubPage.join : NotStartedSubPage.main,
  );

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

  /// Whether [visibleCompletedSessions] has anything — tested cheaply (no build
  /// or sort of the collection) since it gates several CTAs on every rebuild.
  bool get hasCompletedSessions {
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

  /// Join someone's open session if there is one, else start a session and
  /// wait for people.
  void playWithHuman() {
    if (openSessionCount > 0) {
      goToJoinPage();
    } else {
      startNewActivity();
    }
  }

  /// Every start says whether the bot comes along, so an earlier "Play with
  /// Pangea Bot" that was backed out of can't carry into a later start.
  void startNewActivity({bool withBot = false}) {
    if (isLocked) return;
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

  /// Join [roomId] from the join list. With exactly one open role, it is
  /// claimed straight away and the learner lands in the session; otherwise
  /// the session opens for viewing, to pick a role.
  Future<void> joinActivityByRoomId(String roomId) async {
    final client = Matrix.of(context).client;
    final resp = await showFutureLoadingDialog(
      context: context,
      future: () async {
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
      },
    );
    if (resp.isError) return;
    await ActivitySessionPreviewRepo.set(roomId);
    if (!mounted) return;
    if (resp.result == true) {
      NavigationUtil.goToSpaceRoute(roomId, [], context);
    } else {
      _viewSession(roomId);
    }
  }

  /// Whether the learner holds a role in [room] after this: already had one,
  /// or the session had exactly one open role and it was claimed now.
  Future<bool> _claimOnlyOpenRole(Room? room) async {
    final activity = widget.activity;
    if (room == null || activity == null) return false;
    if (room.hasPickedRole) return true;
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
    if (open.length != 1) return false;
    try {
      await room.joinActivity(open.single);
      return true;
    } on RoleException {
      // silent-ok: someone took the seat first; the session opens for
      // viewing instead, where the role picker shows what's left.
      return false;
    }
  }

  @override
  Widget build(BuildContext context) =>
      ActivitySessionStartView(widget.controller, sessionController: this);
}
