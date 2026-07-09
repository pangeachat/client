import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_feedback_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_feedback_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_discovery.dart';
import 'package:fluffychat/features/activity_sessions/discovered_sessions_cache.dart';
import 'package:fluffychat/features/room_summaries/room_summaries_model.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_response_dialog.dart';
import 'package:fluffychat/routes/chat/activity_sessions/archived_session_controller.dart';
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

  /// The backend confirmed the activity no longer exists (404). The page is
  /// read-only: it renders the plan recovered from legacy room state when one
  /// exists, else the archived fallback body — never role selection.
  archived,
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

  /// Whether the open-session summaries are still being fetched (a cache miss —
  /// no data from the map's discovery). Drives the CTA's loading indicator so the
  /// join/start choice never flashes "Start" before the sessions land.
  bool _summariesLoading = true;

  Object? error;

  /// The backend confirmed this activity no longer exists (404). [activity]
  /// may still be populated from the plan embedded in legacy room state; when
  /// it stays null the view renders the archived fallback from room state
  /// alone. Distinct from [error], which is a transient failure worth
  /// retrying.
  bool activityRemoved = false;

  ActivityPlanModel? activity;
  late ActivitySessionSummariesModel _roomSummariesModel;

  bool showInstructions = false;

  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initSummariesFromCache();
    _load();
  }

  /// Seed the summaries from the world map's discovery cache when we arrived from
  /// a pin it already knows is joinable — an instant join list, no fetch. On a
  /// miss the model starts empty and [_summariesLoading] stays true, so
  /// [_loadSummary] fetches and the CTA shows a spinner meanwhile.
  void _initSummariesFromCache() {
    final cached = DiscoveredSessionsCache.instance.forActivity(
      widget.activityId,
    );
    _roomSummariesModel = ActivitySessionSummariesModel(
      cached ?? {},
      activityId: widget.activityId,
    );
    _summariesLoading = cached == null;
  }

  @override
  void didUpdateWidget(covariant ActivitySessionStartPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId ||
        oldWidget.activityId != widget.activityId) {
      setState(() {
        showInstructions = false;
        _initSummariesFromCache();
      });
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
        activityRemoved = false;
      });
      // Gate `loading` on the bounded activity fetch ALONE, so the page always
      // resolves to the activity or the not-found error. The room summaries are
      // non-essential to that render and their fetch can stall, so they load as
      // a self-catching side-effect (below) that must never wedge the spinner
      // (#7085, #7159).
      await _loadActivity();
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
    // Refresh summary-derived UI (member counts, role availability) when it
    // lands; never awaited, so a slow or stalled summary fetch cannot block the
    // activity-or-error render.
    if (mounted) unawaited(_loadSummary());
  }

  Future<void> _loadSummary() async {
    if (!mounted) return;
    // Already satisfied from the map's discovery cache — no server round-trip.
    if (!_summariesLoading) return;
    final Set<String> roomIds = {};
    if (widget.roomId != null) {
      roomIds.add(widget.roomId!);
    }

    // This activity's session rooms across ALL the learner's joined courses —
    // not just a course in scope, since a bare map pin carries no course
    // context. Shared with the world-map pin discovery so both surface the same
    // sessions. See world-map.instructions.md ("Discovering joinable sessions").
    roomIds.addAll(
      await Matrix.of(
        context,
      ).client.courseActivitySessionRoomIds(activityId: widget.activityId),
    );
    if (!mounted) return;

    if (roomIds.isEmpty) {
      if (mounted) setState(() => _summariesLoading = false);
      return;
    }
    try {
      final roomSummariesResponse = await Matrix.of(context).client
          .loadRoomSummaries(
            roomIds.toList(),
            l1Code: MatrixState.pangeaController.userController.userL1Code,
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        _roomSummariesModel = ActivitySessionSummariesModel(
          roomSummariesResponse,
          activityId: widget.activityId,
        );
        _summariesLoading = false;
      });
    } catch (e, s) {
      // Summaries are non-essential (member counts / role availability); a slow
      // or stalled /room_preview must not block or fail the activity render, so
      // degrade to the empty model initialized in initState (#7085, #7159).
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"activityId": widget.activityId},
      );
      if (mounted) setState(() => _summariesLoading = false);
    }
  }

  Future<void> _loadActivity() async {
    // v3: read the canonical activities-v2 plan directly (fetched on open, per
    // the thin-list/full-on-open contract). Localization is choreo's concern,
    // consumed later when this read swaps to a choreo endpoint.
    final lookup = await ActivityPlanRepo.instance.lookup(widget.activityId);
    switch (lookup.status) {
      case ActivityPlanLookupStatus.found:
        activity = lookup.plan;
      case ActivityPlanLookupStatus.removed:
        // Removed-activity fallback ladder (activities.instructions.md):
        // legacy rooms embed the full plan in room state — render it
        // view-only; with no plan anywhere the view shows the archived body
        // built from role/goal state.
        if (!mounted) return;
        final statePlan = activityRoom?.activityPlan;
        activity = statePlan == null
            ? null
            : await ActivityPlanRepo.instance.resolveMedia(statePlan);
        activityRemoved = true;
      case ActivityPlanLookupStatus.failed:
        throw Exception("Activity plan fetch failed");
    }
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
    if (activityRemoved) return SessionState.archived;

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
          summariesLoading: _summariesLoading,
          scrollController: scrollController,
          controller: this,
        );
      case SessionState.archived:
        return ArchivedSession(
          room: activityRoom,
          activity: activity,
          controller: this,
        );
    }
  }
}
