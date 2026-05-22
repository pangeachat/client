import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_start_page.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_state_controller.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_sessions_start_view.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/navigation/navigation_util.dart';
import 'package:fluffychat/pangea/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SelectRoleSession extends StatefulWidget {
  final String? roomId;
  final Room? course;
  final ActivityPlanModel? activity;
  final RoomSummaryResponse? summary;
  final ActivitySessionStartState controller;

  const SelectRoleSession({
    required this.roomId,
    required this.course,
    required this.activity,
    required this.summary,
    required this.controller,
    super.key,
  });

  @override
  SelectRoleSessionController createState() => SelectRoleSessionController();
}

class SelectRoleSessionController extends State<SelectRoleSession>
    implements ActivitySessionStateController {
  String? _selectedRoleId;

  @override
  void didUpdateWidget(covariant SelectRoleSession oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      setState(() => _selectedRoleId = null);
    }
  }

  Room? get activityRoom => widget.roomId != null
      ? Matrix.of(context).client.getRoomById(widget.roomId!)
      : null;

  @override
  String get descriptionText {
    if (_selectedRoleId == null) {
      return activityRoom?.isRoomAdmin ?? false
          ? L10n.of(context).chooseRole
          : L10n.of(context).chooseRoleToParticipate;
    }

    return widget.activity?.roles[_selectedRoleId]?.goal ?? "";
  }

  @override
  bool isRoleShimmering(String id) =>
      _selectedRoleId != null ? false : canSelectRole(id);

  @override
  bool isRoleSelected(String id) => _selectedRoleId == id;

  @override
  bool canSelectRole(String id) {
    final activity = widget.activity;
    if (activity == null) return false;

    final availableRoles = activity.roles;
    final assignedRoles =
        activityRoom?.assignedRoles ??
        widget.summary?.joinedUsersWithRoles ??
        {};

    final unassignedIds = availableRoles.keys
        .where((id) => !assignedRoles.containsKey(id))
        .toList();

    return unassignedIds.contains(id);
  }

  @override
  void selectRole(String id) {
    if (_selectedRoleId == id) return;
    if (mounted) setState(() => _selectedRoleId = id);
  }

  Future<void> confirmRoleSelection() async {
    final activity = widget.activity;
    if (activity == null) {
      ErrorHandler.logError(
        e: "Activity plan model is null in confirmRoleSelection",
        data: {},
      );
      return;
    }

    if (activityRoom?.membership == Membership.join) {
      await showFutureLoadingDialog(
        context: context,
        future: () =>
            activityRoom!.joinActivity(activity.roles[_selectedRoleId]!),
      );
    } else if (widget.roomId != null) {
      await showFutureLoadingDialog(context: context, future: _joinActivity);
    } else {
      final resp = await showFutureLoadingDialog(
        context: context,
        future: () => widget.course!.launchActivityRoom(
          activity,
          activity.roles[_selectedRoleId],
        ),
      );

      if (!resp.isError) {
        NavigationUtil.goToSpaceRoute(resp.result, [], context);
      }
    }

    GoogleAnalytics.startActivity(activity.activityId, widget.roomId ?? '');
  }

  Future<void> _joinActivity() async {
    if (widget.roomId == null) {
      throw Exception(
        "Cannot join activity: room ID is required but not provided",
      );
    }

    final client = Matrix.of(context).client;
    if (activityRoom!.membership != Membership.join) {
      await client.joinRoom(
        widget.roomId!,
        serverName: widget.course?.spaceChildren
            .firstWhereOrNull((child) => child.roomId == widget.roomId)
            ?.via,
      );

      if (activityRoom == null || activityRoom!.membership != Membership.join) {
        await client.waitForRoomInSync(widget.roomId!, join: true);
      }

      if (activityRoom == null || activityRoom!.membership != Membership.join) {
        throw Exception(
          "Failed to join activity room. "
          "Room ID: ${widget.roomId}, "
          "Membership status: ${activityRoom?.membership}",
        );
      }
    }

    final activity = widget.activity;
    if (activity == null) {
      throw StateError("Activity plan model is null in _joinActivity");
    }

    try {
      // Since the method that check for assigned roles needs to know each
      // participant's membership status (to exclude left users), we need
      // to pre-load the room's participants list.
      await activityRoom!.requestParticipants(
        const [Membership.join, Membership.invite, Membership.knock],
        false,
        true,
      );

      await activityRoom!.joinActivity(activity.roles[_selectedRoleId]!);
    } catch (e) {
      if (e is! RoleException) {
        rethrow;
      }
    }

    NavigationUtil.goToSpaceRoute(widget.roomId, [], context);
  }

  @override
  Widget build(BuildContext context) =>
      ActivitySessionStartView(widget.controller, sessionController: this);
}
