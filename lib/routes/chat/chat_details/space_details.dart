import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/navigation/token_params/course_details_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/features/room_summaries/room_summaries_model.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/spaces/space_gone_gate.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_constants.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/local_notifications_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The course (space) details page: owns the course-scoped state — the quest
/// outline, the space children's summaries, and the course-ping / space-gone
/// subscriptions — and renders [SpaceDetailsContent] under the card's header
/// ([SpaceDetailsHeader], the shared panel chrome seating the panel's close
/// control). Non-space rooms render through [ChatDetailsContent] instead —
/// see the shared `ChatDetails` entry.
class SpaceDetails extends StatefulWidget {
  final Room room;
  final Widget? embeddedCloseButton;

  /// The course-page section from the course token to scroll to.
  final SpaceSettingsTabs? activeTab;

  /// Whether [activeTab]'s full subpage ("See all") is pushed over the
  /// course card, from the course token's `<section>/all` param.
  final bool expandedSection;

  const SpaceDetails({
    super.key,
    required this.room,
    this.embeddedCloseButton,
    this.activeTab,
    this.expandedSection = false,
  });

  @override
  SpaceDetailsController createState() => SpaceDetailsController();
}

class SpaceDetailsController extends State<SpaceDetails> {
  late CourseInfoSummariesModel roomSummariesModel;
  late final QuestObjectivesLoader _objectivesProvider;

  /// A ping can land WHILE the course page is open — nothing remounts then,
  /// so re-run the ping capture when this course's timeline gains one.
  StreamSubscription? _coursePingSub;

  StreamSubscription? _spaceGoneSubscription;

  Room get room => widget.room;

  QuestObjectivesLoader get objectivesProvider => _objectivesProvider;

  /// The pushed subpage from the course token, sharing the token's own
  /// expandable-section rule so the panel's back arrow and this page can't
  /// disagree about what is pushed.
  SpaceSettingsTabs? get expandedSection => CourseDetailsTokenParam(
    activeTab: widget.activeTab,
    expanded: widget.expandedSection,
  ).expandedSection;

  String? get _questId => room.coursePlan?.uuid;

  /// The course's per-Mission activity pin (org quests doc, client#7748) —
  /// null when unset, which is the unrestricted default.
  Map<String, List<String>>? get _pinnedActivitiesByObjective =>
      room.teacherMode.pinnedActivitiesByObjective;

  @override
  void initState() {
    super.initState();

    _objectivesProvider = QuestObjectivesLoader(
      client: Matrix.of(context).client,
    );

    roomSummariesModel = CourseInfoSummariesModel(
      {},
      activitiesToCompleteOverride: room.teacherMode.activitiesToUnlockTopic,
    );

    _objectivesProvider.loadOutline(
      _questId,
      pinnedActivitiesByObjective: _pinnedActivitiesByObjective,
      courseRoomId: room.id,
    );
    _loadSummaries();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _handleCoursePing();

      if (!mounted) return;
      await SpaceGoneGate.maybeShowDialog(context, room.id);

      if (!mounted) return;
      Matrix.of(context).showEnableNotificationsDialog(context);
    });

    _coursePingSub = room.client.onSync.stream
        .where((sync) {
          final events = sync.rooms?.join?[room.id]?.timeline?.events;
          return events?.any(
                (e) =>
                    e.content[CoursePingConstants.coursePingActivityId]
                        is String &&
                    e.content[CoursePingConstants.coursePingRoomId] is String,
              ) ??
              false;
        })
        .listen((_) => _handleCoursePing());

    // A deletion or kick while this space is open arrives as a leave sync
    _spaceGoneSubscription = room.client.onSync.stream
        .where((s) => s.rooms?.leave?.containsKey(room.id) ?? false)
        .listen((_) {
          if (mounted) SpaceGoneGate.maybeShowDialog(context, room.id);
        });
  }

  @override
  void didUpdateWidget(covariant SpaceDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      // Clear the previous course's summaries synchronously so the new
      // course can't briefly render the old completion marks while
      // _loadSummaries is in flight.
      roomSummariesModel = CourseInfoSummariesModel(
        {},
        activitiesToCompleteOverride: room.teacherMode.activitiesToUnlockTopic,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) SpaceGoneGate.maybeShowDialog(context, room.id);
      });
      _handleCoursePing();
      _objectivesProvider.loadOutline(
        _questId,
        pinnedActivitiesByObjective: _pinnedActivitiesByObjective,
        courseRoomId: room.id,
      );
      _loadSummaries();
    }

    if (widget.activeTab == SpaceSettingsTabs.course &&
        oldWidget.activeTab != SpaceSettingsTabs.course) {
      _loadSummaries();
    }
  }

  @override
  void dispose() {
    _coursePingSub?.cancel();
    _spaceGoneSubscription?.cancel();
    _objectivesProvider.dispose();
    super.dispose();
  }

  Future<void> _handleCoursePing() async {
    final event = await room.unreadCoursePingEvent;
    if (event == null) {
      // Back on the course with no unread ping left: this course's badge
      // pass (course plan card, session tile) is over. See #8319.
      CoursePingBadgeCache.clearForCourse(room.id);
      return;
    }

    // Stash the pinged activity/session BEFORE setting the read marker — the
    // badges render from this cache for the rest of the visit, while the
    // marker makes the next visit start clean.
    final activityId = event.content[CoursePingConstants.coursePingActivityId];
    final sessionRoomId = event.content[CoursePingConstants.coursePingRoomId];
    if (activityId is String && sessionRoomId is String) {
      CoursePingBadgeCache.set((
        courseId: room.id,
        activityId: activityId,
        sessionRoomId: sessionRoomId,
      ));
    }

    try {
      await room.setReadMarker(event.eventId);
    } catch (_) {}
  }

  /// Open the invite flow beside the card, seated on the most relevant contact
  /// filter (knocking users first). Members are requested first so the knock
  /// check can't run against a not-yet-loaded list (the SDK short-circuits
  /// once the list is complete). See `routing.instructions.md`.
  Future<void> openInvite() async {
    try {
      await room.requestParticipants(
        [Membership.join, Membership.invite, Membership.knock],
        false,
        true,
      );
    } catch (_) {
      // Fall through: the filter degrades to the non-knock default.
    }
    if (!mounted) return;
    context.go(
      WorkspaceNav.openCoursePage(
        GoRouterState.of(context).uri,
        RoomSubpageEnum.invite,
        filter: InvitationFilter.defaultForRoom(room),
      ),
    );
  }

  /// Open a course-management page (edit / access / permissions / change-course)
  /// as the card's DETAIL — a `coursepage` panel beside the card that coexists
  /// when width allows and folds to a push when not, keeping the `?m=` filter
  /// and the rest of the workspace. See `routing.instructions.md`.
  void openCoursePage(RoomSubpageEnum page) => context.go(
    WorkspaceNav.openCoursePage(GoRouterState.of(context).uri, page),
  );

  Future<void> setStarsToUnlockObjective() async {
    // The cap is the lowest-content Mission's earnable stars — the sum
    // of one player's earnable stars (goals per role) across its
    // activities. A value above it could never be satisfied there; the
    // resolver also clamps at resolve time as content changes
    // (quests.instructions.md; #7663).
    int maxStars = 0;
    if (room.coursePlan != null) {
      final resp = await showFutureLoadingDialog(
        context: context,
        future: () async {
          final outline = await QuestRepo.outline(
            room.coursePlan!.uuid,
            // Course-admin read from inside the space: include the
            // owner's private activities so the star cap counts them.
            courseRoomId: room.id,
          );
          return outline.result?.groups
              .map(
                (g) => g.activities.fold(
                  0,
                  (sum, a) => sum + a.plan.earnableStars,
                ),
              )
              .min;
        },
        showError: (e) => false,
      );

      if (resp.result != null) {
        maxStars = resp.result!;
      }
    }
    final current =
        room.teacherMode.starsToUnlockObjective ??
        kDefaultStarsToUnlockObjective;
    if (!mounted) return;
    final resp = await showTextInputDialog(
      context: context,
      title: L10n.of(context).starsToUnlockObjectiveTitle,
      keyboardType: TextInputType.number,
      maxLength: 2,
      maxLines: 1,
      validator: (input) {
        final value = int.tryParse(input);
        if (value == null || value < 1) {
          return L10n.of(context).enterNumber;
        }
        if (maxStars > 0 && value > maxStars) {
          return L10n.of(context).maxStarsPerMissionWarning(maxStars);
        }
        return null;
      },
      initialText: "$current",
    );

    if (resp == null || !mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => room.setTeacherMode(
        room.teacherMode.copyWith(starsToUnlockObjective: int.parse(resp)),
      ),
    );
  }

  Future<void> leaveCourse() async {
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).areYouSure,
      okLabel: L10n.of(context).leave,
      cancelLabel: L10n.of(context).no,
      message: L10n.of(context).leaveSpaceDescription,
      isDestructive: true,
    );
    if (confirmed != OkCancelResult.ok || !mounted) return;
    final resp = await showFutureLoadingDialog(
      context: context,
      future: room.leaveSpace,
    );
    if (!resp.isError && mounted) {
      // Leaving a course is the World/home reset: drop every panel and the
      // `?c=` scope, back to the world map at its personal default.
      context.go(WorkspaceNav.clearAll());
    }
  }

  Future<void> addGroupChat() async {
    final groupName = await showTextInputDialog(
      context: context,
      title: L10n.of(context).createGroup,
      hintText: L10n.of(context).groupName,
      minLines: 1,
      maxLines: 1,
      maxLength: 64,
      validator: (text) {
        if (text.isEmpty) {
          return L10n.of(context).pleaseChoose;
        }
        return null;
      },
      okLabel: L10n.of(context).create,
      cancelLabel: L10n.of(context).cancel,
    );
    if (groupName == null) return;

    final resp = await showFutureLoadingDialog<String>(
      context: context,
      future: () async {
        final newRoomId = await Matrix.of(context).client.createPangeaGroupChat(
          groupName,
          initialState: [
            await Matrix.of(context).client.generateCustomJoinRules(
              JoinRules.knockRestricted,
              allowRoomId: room.id,
            ),
          ],
          powerLevelContentOverride: RoomDefaults.defaultPowerLevelsContent(),
        );

        try {
          await room.addToSpace(newRoomId);
          final newRoom = Matrix.of(context).client.getRoomById(newRoomId);
          if (newRoom != null && newRoom.spaceParents.isEmpty) {
            await Matrix.of(context).client
                .waitForRoomInSync(newRoomId)
                .timeout(Duration(seconds: 10));
          }
          return newRoomId;
        } catch (e, s) {
          ErrorHandler.logError(
            e: e,
            s: s,
            data: {'newRoomId': newRoomId, 'spaceId': room.id},
            level: e is TimeoutException
                ? SentryLevel.warning
                : SentryLevel.error,
          );

          if (e is TimeoutException) {
            return newRoomId;
          } else {
            rethrow;
          }
        }
      },
    );

    if (resp.isError || resp.result == null || !mounted) return;
    NavigationUtil.goToSpaceRoute(resp.result, ['invite'], context);
  }

  Future<void> _loadSummaries() async {
    try {
      final roomIds = room.spaceChildren
          .map((c) => c.roomId)
          .whereType<String>()
          .toList();

      final roomSummariesResponse = await room.client.loadRoomSummaries(
        roomIds,
        l1Code: MatrixState.pangeaController.userController.userL1Code,
      );

      if (!mounted) return;
      setState(() {
        roomSummariesModel = CourseInfoSummariesModel(
          roomSummariesResponse,
          activitiesToCompleteOverride:
              room.teacherMode.activitiesToUnlockTopic,
        );
      });
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "message": "Failed to load activity summaries",
          "roomId": room.id,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: L10n.of(context).pageLabel(L10n.of(context).courseDetails),
      container: true,
      child: Scaffold(
        body: Column(
          children: [
            SpaceDetailsHeader(this, room),
            Expanded(
              // Top inset only: sections pad themselves horizontally
              // ([SpaceDetailsContent.sectionPadding]) so the dividers
              // between them run edge-to-edge (#8357 design).
              child: Padding(
                padding: const EdgeInsetsGeometry.only(top: 16.0),
                child: MaxWidthBody(
                  maxWidth: 900,
                  showBorder: false,
                  withScrolling: false,
                  child: SpaceDetailsContent(this, room),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
