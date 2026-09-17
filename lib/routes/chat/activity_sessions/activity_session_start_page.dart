import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import 'package:fluffychat/features/analytics_data/analytics_updater_mixin.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_close_location.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/room_summaries/activity_session_previews_extension.dart';
import 'package:fluffychat/features/room_summaries/room_summaries_model.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_response_dialog.dart';
import 'package:fluffychat/pangea/extensions/leave_room_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/archived_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/confirmed_role_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/chat/activity_sessions/full_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/not_started_session_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/select_role_session_controller.dart';
import 'package:fluffychat/routes/chat/chat_details/delete_room_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
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

  /// The backend confirmed the activity no longer exists (404) AND there is a
  /// session to review. The page is read-only: it renders the plan recovered
  /// from legacy room state when one exists, else the archived fallback body —
  /// never role selection.
  archived,
}

/// Whether a confirmed-removed activity renders the read-only archived view
/// and its "no longer supported" notice.
///
/// The removed-activity ladder is scoped to session ROOMS: every rung renders
/// what the room itself holds — roles, stars, timeline — so a learner or their
/// teacher can always reopen an old session and review the work done there
/// (activities.instructions.md, "Removed or unresolvable activities"). Reached
/// WITHOUT a session, as a bare world-map pin is, there is no such thing to
/// review: the archived body would render empty and the notice would tell the
/// learner an activity they never ran is out of date (#7918). That case is a
/// plain not-found instead.
bool archivedSessionGate({
  required bool activityRemoved,
  required bool hasSessionRoom,
}) => activityRemoved && hasSessionRoom;

/// Whether the archived view offers a way out of the session room.
///
/// A removed activity's session can never be continued or finished — no one
/// else can be invited into it — so without this the room sits in the chat
/// list forever with no exit (#8064). Offered only to a learner actually
/// joined: an observer previewing the room has nothing to leave.
bool archivedLeaveGate({
  required bool isArchived,
  required Membership? membership,
}) => isArchived && membership == Membership.join;

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

// AnalyticsUpdater: this page is reachable from the world map with no chat
// open, so it must host its own XP/growth listeners for the collectable
// vocab chips (#8613).
class ActivitySessionStartState extends State<ActivitySessionStartPage>
    with AnalyticsUpdater {
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
    // Opening the pinged activity is what lets the next course-page visit
    // clear the ping badges (#8319). The session tile badge still renders
    // from the cache while this page is up.
    CoursePingBadgeCache.markFollowed(widget.activityId);
    _initSummariesFromCache();
    _load();
  }

  /// Seed the summaries from the world map's discovery cache when we arrived from
  /// a pin it already knows is joinable — an instant join list, no spinner. On a
  /// miss the model starts empty and [_summariesLoading] stays true, so the CTA
  /// shows a spinner until [_loadSummary] lands. Either way [_loadSummary] still
  /// fetches: the cache can hold a session whose members have since left, which
  /// nothing in B's sync will ever correct (#8150), so a seeded render is a
  /// stale-while-revalidate, not a fetch skip.
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
    final client = Matrix.of(context).client;

    // This activity's session rooms across ALL the learner's joined courses —
    // not just a course in scope, since a bare map pin carries no course
    // context. Discovered server-side by the space-scoped
    // activity_session_previews module: one batched read of the joined course
    // spaces returns previews for only this activity's session rooms, complete
    // regardless of how many rooms a course holds (#7982). See
    // world-map.instructions.md ("Discovering joinable sessions").
    final courseSpaceIds = client.joinedCourseSpaces.map((r) => r.id).toList();

    // Rooms the module can't see: the deep-linked room itself, and sessions the
    // learner is invited to (possibly outside any shared course) — in the room
    // list, but only a preview carries accurate seats, and without this a green
    // invited pin dead-ends at a joinless start page (#7488). These keep the
    // per-room room_preview read.
    final Set<String> extraRoomIds = {
      ?widget.roomId,
      ...client.rooms
          .where(
            (r) =>
                r.membership == Membership.invite &&
                r.activityId == widget.activityId,
          )
          .map((r) => r.id),
    };

    if (courseSpaceIds.isEmpty && extraRoomIds.isEmpty) {
      if (mounted) setState(() => _summariesLoading = false);
      return;
    }
    try {
      final l1Code = MatrixState.pangeaController.userController.userL1Code;
      final results = await Future.wait([
        courseSpaceIds.isNotEmpty
            ? client.loadActivitySessionPreviews(
                courseSpaceIds,
                activityId: widget.activityId,
                l1Code: l1Code,
              )
            : Future.value(<String, RoomSummaryResponse>{}),
        extraRoomIds.isNotEmpty
            ? client.loadRoomSummaries(extraRoomIds.toList(), l1Code: l1Code)
            : Future.value(<String, RoomSummaryResponse>{}),
      ]).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        _roomSummariesModel = ActivitySessionSummariesModel({
          ...results[0],
          ...results[1],
        }, activityId: widget.activityId);
        _summariesLoading = false;
      });
      // Write the fresh space-scoped previews back so views rendering off the
      // cache (the course card's Open state) correct themselves now instead of
      // on the map's next discovery pass (#8150). Only results[0]: the per-room
      // extras (deep-linked / invited rooms) are outside what discovery caches.
      if (courseSpaceIds.isNotEmpty) {
        DiscoveredSessionsCache.instance.updateActivity(
          widget.activityId,
          results[0],
        );
      }
    } catch (e, s) {
      // Summaries are non-essential (member counts / role availability); a slow
      // or stalled preview read must not block or fail the activity render, so
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
    //
    // On an existing session room, read at the room's pinned version, not the
    // latest: role ids re-mint on owner edits, and the room's role state (and
    // the session previews derived from it) key on the pinned ids, so a latest
    // read makes every assignedRoles lookup miss and renders occupied role
    // cards as OPEN (#8213). Null (no room, or legacy embedded room) reads the
    // latest, as before.
    final lookup = await ActivityPlanRepo.instance.lookup(
      widget.activityId,
      version: activityRoom?.pinnedActivityVersionId,
    );
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

  /// Copy the activity's standalone shareable link to the clipboard. Mirrors
  /// the course [ShareRoomButton]: copy-only (never the OS share sheet), and
  /// `hideCurrentSnackBar` + `showCloseIcon` so rapid taps replace the toast
  /// (with a dismissal X) instead of queueing a backlog. See
  /// activity-start-page.instructions.md.
  ///
  /// Path URL strategy (main.dart) means the link carries no `#` — on web a
  /// fragment is ignored (`shouldNavigateToIncomingUri` is false there) and the
  /// link would dead-end on the world map. A first-class UUID rides the pretty
  /// `/<uuid>` contract that LegacyRedirects folds in.
  Future<void> copyActivityLink() async {
    final activityId = widget.activityId;
    final path = PRoutes.isWorldObjectId(activityId)
        ? PRoutes.worldObject(activityId)
        : '${PRoutes.world}?left='
              '${ActivityPanelToken(ActivityTokenParam(activityId: activityId)).encode()}';
    await Clipboard.setData(
      ClipboardData(text: '${Environment.frontendURL}$path'),
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBarAnnounced(
      SnackBar(
        content: Text(L10n.of(context).copiedToClipboard),
        showCloseIcon: true,
      ),
    );
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

  /// See [archivedSessionGate]. Also read by the view, which picks the
  /// archived body over the not-found error on the same condition.
  bool get isArchived => archivedSessionGate(
    activityRemoved: activityRemoved,
    hasSessionRoom: widget.roomId != null,
  );

  /// See [archivedLeaveGate].
  bool get canLeaveArchivedSession => archivedLeaveGate(
    isArchived: isArchived,
    membership: activityRoom?.membership,
  );

  /// The learner has confirmed a role and is waiting for the room to fill, but
  /// the activity chat hasn't begun — the one live state where they can still
  /// back out via the app-bar "…" menu. See activity-start-page.instructions.md.
  bool get isPendingSession {
    final room = activityRoom;
    return _sessionState == SessionState.confirmedRole &&
        room != null &&
        !room.isActivityStarted;
  }

  /// Only the room's admin (its creator, under the default power levels) can
  /// delete it for everyone; a plain member can only leave — mirroring chat's
  /// own leave/delete gating.
  bool get canDeleteSession => activityRoom?.isRoomAdmin == true;

  /// Leave the current session room and close its panel. Shared by the
  /// waiting-room menu and the archived fallback's lone exit — a session that
  /// can never continue would otherwise sit in the chat list forever (#8064).
  /// An archived session is often one the homeserver has already forgotten, so
  /// it leaves via [LeaveRoomExtension.leaveIgnoringUnknownRoom].
  Future<void> leaveSession() => _exitSessionRoom(
    action: (room) => room.leaveIgnoringUnknownRoom(),
    message: L10n.of(context).leaveRoomDescription,
    okLabel: L10n.of(context).leave,
  );

  /// Delete the session room for everyone — admin-only ([canDeleteSession]),
  /// the same purge chat's delete uses — then close its panel.
  Future<void> deleteSession() => _exitSessionRoom(
    action: (room) => room.delete(),
    message: L10n.of(context).deleteChatDesc,
    okLabel: L10n.of(context).delete,
  );

  /// Confirm, run [action] on the session room, wait for the resulting leave to
  /// land in sync, then close the panel — so the room is gone from the chat
  /// list before its panel closes.
  Future<void> _exitSessionRoom({
    required Future<void> Function(Room room) action,
    required String message,
    required String okLabel,
  }) async {
    final room = activityRoom;
    if (room == null) return;

    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).areYouSure,
      message: message,
      okLabel: okLabel,
      cancelLabel: L10n.of(context).cancel,
      isDestructive: true,
    );
    if (confirmed != OkCancelResult.ok || !mounted) return;

    final result = await showFutureLoadingDialog(
      context: context,
      future: () => action(room),
    );
    if (result.isError || !mounted) return;

    final left = Matrix.of(context).client.getRoomById(room.id);
    if (left != null && left.membership != Membership.leave) {
      await Matrix.of(context).client.waitForRoomInSync(room.id, leave: true);
    }

    if (!mounted) return;
    closeOwnRoomPanel(context, room.id);
  }

  SessionState get _sessionState {
    if (isArchived) return SessionState.archived;

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
