import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/bot_activty_role_room_extension.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_sessions_start_view.dart';
import 'package:fluffychat/routes/chat/activity_sessions/bot_join_error_dialog.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/session_presence_tracker.dart';
import 'package:fluffychat/routes/chat/activity_sessions/waiting_room_join_watcher.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ConfirmedRoleSession extends StatefulWidget {
  final Room room;
  final String activityId;
  final ActivityPlanModel? activity;
  final ActivitySessionStartState controller;

  const ConfirmedRoleSession({
    super.key,
    required this.room,
    required this.activityId,
    required this.controller,
    this.activity,
  });

  @override
  ConfirmedRoleSessionController createState() =>
      ConfirmedRoleSessionController();
}

class ConfirmedRoleSessionController extends State<ConfirmedRoleSession>
    implements ActivitySessionStateController {
  Timer? _pingCooldown;
  final _goalsHandler = GoalsSubscriptionHandler();

  /// Ticks every second, driving the waiting timer.
  /// Only the widgets that read it rebuild.
  final ValueNotifier<DateTime> clock = ValueNotifier(DateTime.now());
  Timer? _clockTimer;

  /// Live presence of the course's members, kept current by the SDK's
  /// presence stream — no polling.
  late final SessionPresenceTracker presence;

  /// The course's joined members other than you and the bot; null until
  /// loaded, or when the session has no source course.
  final ValueNotifier<List<String>?> coursemateIds = ValueNotifier(null);

  /// The learner went to practice from here, so the button now reads
  /// "Practice again".
  bool practicedWhileWaiting = false;

  @override
  void initState() {
    super.initState();
    // Back in the waiting room: no need to be told someone joined.
    WaitingRoomJoinWatcher.stop();
    presence = SessionPresenceTracker(widget.room.client);
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => clock.value = DateTime.now(),
    );
    _loadCoursemates();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _goalsHandler.init(widget.room.id, context, setState, () => mounted);
  }

  @override
  void dispose() {
    _pingCooldown?.cancel();
    _clockTimer?.cancel();
    clock.dispose();
    presence.dispose();
    coursemateIds.dispose();
    _goalsHandler.cancel();
    super.dispose();
  }

  /// When the session was created — what the waiting timer counts from, so
  /// it survives leaving and coming back.
  DateTime? get waitingSince {
    final create = widget.room.getState(EventTypes.RoomCreate);
    return create is Event ? create.originServerTs : null;
  }

  /// Coursemates online right now — the avatar presence dot's rule.
  int get onlineCoursemateCount =>
      presence.onlineCount(coursemateIds.value ?? const []);

  Future<void> _loadCoursemates() async {
    final course = this.course;
    if (course == null) return;
    final client = widget.room.client;
    try {
      final members = await course.requestParticipants([Membership.join]);
      final ids = [
        for (final member in members)
          if (member.id != client.userID && member.id != BotName.byEnvironment)
            member.id,
      ];
      if (!mounted) return;
      presence.watch(ids);
      coursemateIds.value = ids;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': widget.room.id},
        level: SentryLevel.warning,
      );
    }
  }

  /// Practice vocab while waiting. Practice opens beside the session on wide
  /// screens; wherever it opens, the learner is told when someone joins.
  void practiceWhileWaiting() {
    setState(() => practicedWhileWaiting = true);
    WaitingRoomJoinWatcher.watch(widget.room);
    context.go(
      WorkspaceNav.openPractice(
        GoRouterState.of(context).uri,
        ConstructTypeEnum.vocab,
      ),
    );
  }

  /// The course whose roster the ping reaches and the active count reads:
  /// the one this session was launched from, never a course it was merely
  /// fanned out into ([Room.sourceCourse]). The page's borrowed course context
  /// can be any space parent, so it can't drive a write against the course
  /// (#8097). The waiting room names it, so a learner browsing another course
  /// can see which one this is (#9333 prototype).
  Room? get course => widget.room.sourceCourse;

  bool get showPingCourse => course != null;

  bool get showInviteOptions => widget.room.isRoomAdmin;

  // Gate on the bot's live seat, not the sticky pangea.bot_participant
  // marker: the marker survives the bot leaving, and the button must come
  // back whenever the bot holds no role (#8099).
  bool get enablePlayWithBot =>
      showInviteOptions && !widget.room.botHasActivityRole;

  @override
  String get descriptionText {
    final roles = widget.room.numRemainingRoles;
    return roles > 1
        ? L10n.of(context).waitingToFillRole(roles)
        : L10n.of(context).waitingToFillOneRole;
  }

  @override
  bool get goalsStartCollapsed => true;

  @override
  List<ActivityRoleGoal>? get selectedRoleGoals {
    final roleId = widget.room.ownRoleState?.id;
    if (roleId == null) return null;
    return widget.activity?.roles[roleId]?.allGoals;
  }

  @override
  Set<String> get selectedRoleCompletedGoalIds {
    final roleId = widget.room.ownRoleState?.id;
    if (roleId == null) return {};
    return _goalsHandler.scan(
      roleId,
      Matrix.of(context).client,
      activityId: widget.activityId,
      activity: widget.activity,
    );
  }

  @override
  bool isRoleSelected(String id) => widget.room.ownRoleState?.id == id;

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
  bool get showRoleCards => true;

  @override
  bool get showDescriptionSection => true;

  @override
  Set<String> completedGoalIdsForRole(String id) => {};

  Future<bool> get canPingParticipants async {
    final course = this.course;
    if (course == null) return false;
    if (_pingCooldown != null && _pingCooldown!.isActive) return false;

    final courseParticipants = await course.requestParticipants(
      [Membership.join, Membership.invite, Membership.knock],
      false,
      true,
    );

    final roomParticipants = await widget.room.requestParticipants(
      [Membership.join, Membership.invite, Membership.knock],
      false,
      true,
    );

    for (final p in courseParticipants) {
      if (p.id == BotName.byEnvironment) continue;
      if (roomParticipants.any((rp) => rp.id == p.id)) continue;
      return true;
    }

    return false;
  }

  void inviteFriends() {
    NavigationUtil.goToSpaceRoute(widget.room.id, ['invite'], context);
  }

  Future<void> pingCourse() =>
      showFutureLoadingDialog(context: context, future: _pingCourse);

  Future<void> _pingCourse() async {
    final course = this.course;
    if (course == null) {
      throw Exception("Activity was not launched from a course");
    }

    if (!(await canPingParticipants)) {
      throw Exception("Ping is on cooldown");
    }

    _pingCooldown?.cancel();
    _pingCooldown = Timer(const Duration(minutes: 1), () {
      _pingCooldown = null;
      if (mounted) setState(() {});
    });

    await course.sendActivityPing(
      L10n.of(context).pingParticipantsNotification(
        widget.room.client.userID!.localpart ?? widget.room.client.userID!,
        widget.room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
      ),
      activityId: widget.activityId,
      sessionRoomId: widget.room.id,
    );

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).pingSent, textAlign: TextAlign.center),
          duration: const Duration(milliseconds: 2000),
        ),
      );
    }
  }

  Future<void> playWithBot() async {
    await showDialog(
      context: context,
      builder: (_) => PlayWithBotLoadingDialog(room: widget.room),
    );
  }

  @override
  Widget build(BuildContext context) =>
      ActivitySessionStartView(widget.controller, sessionController: this);
}
