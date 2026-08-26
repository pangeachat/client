import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/bot_activty_role_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_target_ids.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_sessions_start_view.dart';
import 'package:fluffychat/routes/chat/activity_sessions/bot_join_error_dialog.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_extension.dart';
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

  @override
  void initState() {
    super.initState();
    // This screen owns the invite / play-with-bot controls the tutorial points
    // at, so it registers as their owner. See tutorials.instructions.md.
    MatrixState.tutorialOverlayController.registerLauncher(
      TutorialEnum.activityInvite,
      _launchInviteTutorial,
    );
    _scheduleInviteTutorialRequest();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _goalsHandler.init(widget.room.id, context, setState, () => mounted);
    // Re-asked on dependency changes too: whether the invite controls exist
    // turns on room admin state, which can land after the first build.
    _scheduleInviteTutorialRequest();
  }

  @override
  void dispose() {
    _pingCooldown?.cancel();
    _goalsHandler.cancel();
    MatrixState.tutorialOverlayController
      ..unregisterLauncher(TutorialEnum.activityInvite, _launchInviteTutorial)
      // Nothing can show the remaining steps once the waiting room is gone, and
      // giving the sequence up here is what lets the goal-header one start when
      // the chat opens.
      ..releaseSequence(TutorialSequences.activityInviteSequence);
    super.dispose();
  }

  /// Always post-frame: the request launches the tutorial synchronously, and the
  /// controls it lights have to be laid out before the spotlight is placed.
  void _scheduleInviteTutorialRequest() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Which tutorials this learner has seen lives on their profile, and an
      // unloaded profile reports every one as already seen. Waiting for it is
      // the difference between offering this a moment later and never at all.
      await MatrixState.pangeaController.userController.initCompleter.future;
      // Offered only where the controls actually exist: a learner who is not the
      // room admin has no invite options, so there would be nothing to light.
      if (!mounted || !showInviteOptions) return;
      MatrixState.tutorialOverlayController.requestSequence(
        TutorialSequences.activityInviteSequence,
      );
    });
  }

  Future<void> _launchInviteTutorial() async {
    if (!mounted || !showInviteOptions) return;
    MatrixState.tutorialOverlayController.launchTutorial(
      context: context,
      tutorial: TutorialModel(
        tutorialType: TutorialEnum.activityInvite,
        stepsData: [
          TutorialStepData(
            // Both controls lit as one group: the message is that either way
            // works, so highlighting one over the other would misread.
            targetKeys: const [
              TutorialTargetIds.activityPlayWithBot,
              TutorialTargetIds.activityInviteFriends,
            ],
            canShowNextStep: () => true,
          ),
        ],
      ),
      isFocused: true,
    );
  }

  /// The course whose roster the ping reaches: the one this session was launched
  /// from, never a course it was merely fanned out into ([Room.sourceCourse]).
  /// The page's borrowed course context can be any space parent, so it can't
  /// drive a write against the course (#8097).
  Room? get _course => widget.room.sourceCourse;

  bool get showPingCourse => _course != null;

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
    final course = _course;
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
    final course = _course;
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
