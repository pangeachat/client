import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_feedback_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_feedback_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/room_summaries/room_summaries_model.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_response_dialog.dart';
import 'package:fluffychat/routes/chat/activity_sessions/confirmed_role_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/full_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/not_started_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/select_role_session_controller.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum SessionState {
  /// The room hasn't been created yet.
  notStarted,

  /// The room exists and all roles are full. The user cannot get a role in this session.
  selectedSessionFull,

  /// The room exists or is being created, but the user hasn't confirmed a role yet.
  selectRole,

  /// The user has confirmed their role.
  confirmedRole,
}

class ActivitySessionStartPage extends StatefulWidget {
  final String activityId;
  final String? roomId;
  final String? parentId;
  final bool launch;

  const ActivitySessionStartPage({
    super.key,
    required this.activityId,
    required this.parentId,
    this.roomId,
    this.launch = false,
  });

  @override
  ActivitySessionStartState createState() => ActivitySessionStartState();
}

class ActivitySessionStartState extends State<ActivitySessionStartPage> {
  bool loading = true;
  Object? error;

  ActivityPlanModel? activity;
  late ActivitySessionSummariesModel _roomSummariesModel;

  bool showInstructions = false;

  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    _roomSummariesModel = ActivitySessionSummariesModel(
      {},
      activityId: widget.activityId,
    );

    _load();
  }

  @override
  void didUpdateWidget(covariant ActivitySessionStartPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId ||
        oldWidget.activityId != widget.activityId) {
      setState(() => showInstructions = false);
      _load();
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  Room? get activityRoom => widget.roomId != null
      ? Matrix.of(context).client.getRoomById(widget.roomId!)
      : null;

  Room? get courseParent => widget.parentId != null
      ? Matrix.of(context).client.getRoomById(widget.parentId!)
      : null;

  Map<String, ActivityRoleModel> get assignedRoles {
    final roomId = widget.roomId;
    if (roomId == null) return {};

    final activityRoom = this.activityRoom;
    if (activityRoom != null && activityRoom.membership == Membership.join) {
      return activityRoom.assignedRoles ?? {};
    }

    return _roomSummariesModel.getRoomSummary(roomId)?.joinedUsersWithRoles ??
        {};
  }

  void toggleInstructions() {
    setState(() {
      showInstructions = !showInstructions;
    });
  }

  Future<void> _load() async {
    try {
      setState(() {
        loading = true;
        error = null;
      });
      await Future.wait([_loadSummary(), _loadActivity()]);
    } catch (e, s) {
      error = e;
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "activityId": widget.activityId,
          "roomId": widget.roomId,
          "parentId": widget.parentId,
        },
      );
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _loadSummary() async {
    final Set<String> roomIds = {};
    if (widget.roomId != null) {
      roomIds.add(widget.roomId!);
    }

    final course = courseParent;
    if (course != null) {
      roomIds.addAll(
        course.spaceChildren.map((c) => c.roomId).whereType<String>(),
      );
    }

    if (roomIds.isEmpty) return;
    final roomSummariesResponse = await Matrix.of(context).client
        .loadRoomSummaries(
          roomIds.toList(),
          l1Code: MatrixState.pangeaController.userController.userL1Code,
        );

    _roomSummariesModel = ActivitySessionSummariesModel(
      roomSummariesResponse,
      activityId: widget.activityId,
    );
  }

  Future<void> _loadActivity() async {
    // v3: read the canonical activities-v2 plan directly (fetched on open, per
    // the thin-list/full-on-open contract). Localization is choreo's concern,
    // consumed later when this read swaps to a choreo endpoint.
    final plan = await ActivityPlanRepo.instance.getPlan(widget.activityId);
    if (plan == null) {
      throw Exception("Activity not found");
    }
    activity = plan;
  }

  Future<void> submitActivityFeedback() async {
    final feedback = await showDialog<String?>(
      context: context,
      builder: (context) {
        return FeedbackDialog(
          title: L10n.of(context).feedbackTitle,
          onSubmit: (feedback) {
            Navigator.of(context).pop(feedback);
          },
        );
      },
    );

    if (feedback == null || feedback.isEmpty) {
      return;
    }

    final resp = await showFutureLoadingDialog(
      context: context,
      future: () => ActivityFeedbackRepo.submitFeedback(
        ActivityFeedbackRequest(
          activityId: widget.activityId,
          feedbackText: feedback,
          userId: Matrix.of(context).client.userID!,
          userL1: MatrixState.pangeaController.userController.userL1Code!,
          userL2: MatrixState.pangeaController.userController.userL2Code!,
        ),
      ),
    );

    if (resp.isError) {
      return;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return FeedbackResponseDialog(
          title: L10n.of(context).feedbackTitle,
          feedback: resp.result!.userFriendlyResponse,
          description: L10n.of(context).feedbackRespDesc,
        );
      },
    );
  }

  SessionState get _sessionState {
    final roomExists = widget.roomId != null;
    final userIsCreatingRoom = widget.launch;

    final room = activityRoom;
    final userIsInRoom = room != null && room.membership == Membership.join;
    final userHasPickedRole = userIsInRoom && room.hasPickedRole;

    if (!roomExists) {
      if (!userIsCreatingRoom) {
        return SessionState.notStarted;
      }
      return SessionState.selectRole;
    }

    if (!userIsInRoom) {
      final assigned = assignedRoles.length;
      final total = activity?.roles.length ?? 0;
      final canSelectRole = assigned < total;

      if (!canSelectRole) {
        return SessionState.selectedSessionFull;
      }

      return SessionState.selectRole;
    }

    if (!userHasPickedRole) {
      return SessionState.selectRole;
    }

    return SessionState.confirmedRole;
  }

  @override
  Widget build(BuildContext context) {
    final course = courseParent;
    switch (_sessionState) {
      case SessionState.selectRole:
        final roomId = widget.roomId;
        final summary = roomId != null
            ? _roomSummariesModel.getRoomSummary(roomId)
            : null;

        return SelectRoleSession(
          activity: activity,
          summary: summary,
          roomId: widget.roomId,
          course: course,
          controller: this,
        );
      case SessionState.confirmedRole:
        return ConfirmedRoleSession(
          room: activityRoom!,
          activityId: widget.activityId,
          activity: activity,
          course: course,
          controller: this,
        );
      case SessionState.selectedSessionFull:
        return FullSession(course: course, controller: this);
      case SessionState.notStarted:
        return NotStartedSession(
          course: course,
          activity: activity,
          activityId: widget.activityId,
          summaries: _roomSummariesModel,
          scrollController: scrollController,
          controller: this,
        );
    }
  }
}
