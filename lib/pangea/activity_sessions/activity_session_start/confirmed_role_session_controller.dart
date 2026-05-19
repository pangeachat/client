import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_start_page.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_state_controller.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_sessions_start_view.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/bot_join_error_dialog.dart';
import 'package:fluffychat/pangea/bot/bot_room_extension.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/navigation/navigation_util.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class ConfirmedRoleSession extends StatefulWidget {
  final Room room;
  final Room? course;
  final String activityId;
  final ActivitySessionStartState controller;

  const ConfirmedRoleSession({
    super.key,
    required this.room,
    required this.activityId,
    required this.controller,
    this.course,
  });

  @override
  ConfirmedRoleSessionController createState() =>
      ConfirmedRoleSessionController();
}

class ConfirmedRoleSessionController extends State<ConfirmedRoleSession>
    implements ActivitySessionStateController {
  ConfirmedRoleSessionController();

  Timer? _pingCooldown;

  @override
  void dispose() {
    _pingCooldown?.cancel();
    super.dispose();
  }

  bool get showPingCourse => widget.course != null;

  bool get showInviteOptions => widget.room.isRoomAdmin;

  @override
  String get descriptionText =>
      L10n.of(context).waitingToFillRole(widget.room.numRemainingRoles);

  @override
  bool isRoleSelected(String id) => widget.room.ownRoleState?.id == id;

  @override
  bool isRoleShimmering(String id) => false;

  @override
  bool canSelectRole(String id) => false;

  @override
  void selectRole(String id) {}

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
    final resp = await showFutureLoadingDialog(
      context: context,
      future: _playWithBot,
      showError: (e) => e is! TimeoutException,
    );

    if (!mounted) return;
    if (resp.isError && resp.error is TimeoutException) {
      await showDialog(
        context: context,
        builder: (_) => const BotJoinErrorDialog(),
      );
    }
  }

  Future<void> _playWithBot() async {
    if (await isBotRoomMember) {
      throw Exception("Bot is a member of the room");
    }

    final Future<({String roomId, StrippedStateEvent state})?> future = widget
        .room
        .client
        .onRoomState
        .stream
        .where(
          (state) =>
              state.roomId == widget.room.id &&
              state.state.type == PangeaEventTypes.activityRole &&
              state.state.senderId == BotName.byEnvironment,
        )
        .first;

    widget.room.invite(BotName.byEnvironment);
    await future.timeout(const Duration(seconds: 5));
  }

  @override
  Widget build(BuildContext context) =>
      ActivitySessionStartView(widget.controller, sessionController: this);
}
