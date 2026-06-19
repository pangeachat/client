import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/bot_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_sessions_start_view.dart';
import 'package:fluffychat/routes/chat/activity_sessions/bot_join_error_dialog.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ConfirmedRoleSession extends StatefulWidget {
  final Room room;
  final Room? course;
  final String activityId;
  final ActivityPlanModel? activity;
  final ActivitySessionStartState controller;

  const ConfirmedRoleSession({
    super.key,
    required this.room,
    required this.activityId,
    required this.controller,
    this.course,
    this.activity,
  });

  @override
  ConfirmedRoleSessionController createState() =>
      ConfirmedRoleSessionController();
}

class ConfirmedRoleSessionController extends State<ConfirmedRoleSession>
    implements ActivitySessionStateController {
  ConfirmedRoleSessionController();

  Timer? _pingCooldown;
  final _goalsHandler = GoalsSubscriptionHandler();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _goalsHandler.init(widget.room.id, context, setState, () => mounted);
  }

  @override
  void dispose() {
    _pingCooldown?.cancel();
    _goalsHandler.cancel();
    super.dispose();
  }

  bool get showPingCourse => widget.course != null;

  bool get showInviteOptions => widget.room.isRoomAdmin;

  @override
  String get descriptionText =>
      L10n.of(context).waitingToFillRole(widget.room.numRemainingRoles);

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
    final course = widget.course;
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

  Future<bool> get isBotRoomMember => widget.room.botIsInRoom;

  void inviteFriends() {
    NavigationUtil.goToSpaceRoute(widget.room.id, ['invite'], context);
  }

  Future<void> pingCourse() =>
      showFutureLoadingDialog(context: context, future: _pingCourse);

  Future<void> _pingCourse() async {
    if (widget.course == null) {
      throw Exception("Activity is not part of a course");
    }

    if (!(await canPingParticipants)) {
      throw Exception("Ping is on cooldown");
    }

    _pingCooldown?.cancel();
    _pingCooldown = Timer(const Duration(minutes: 1), () {
      _pingCooldown = null;
      if (mounted) setState(() {});
    });

    await widget.room.courseParent!.sendEvent({
      "body": L10n.of(context).pingParticipantsNotification(
        widget.room.client.userID!.localpart ?? widget.room.client.userID!,
        widget.room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
      ),
      "msgtype": "m.text",
      "pangea.activity.session_room_id": widget.room.id,
      "pangea.activity.id": widget.activityId,
    });

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
