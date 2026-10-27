import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;

import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_access_handler.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_builder.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/features/join_codes/space_code_controller.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/course_cta_row.dart';
import 'package:fluffychat/routes/courses/own/selected_course_page.dart';
import 'package:fluffychat/routes/courses/own/selected_course_view.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PublicCoursePreview extends StatefulWidget {
  final String? roomID;
  final Widget? closeButton;

  /// Start my own's picked quest, when this course was opened instead of it
  /// (#9590).
  final String? ownQuestId;

  const PublicCoursePreview({
    super.key,
    required this.roomID,
    this.closeButton,
    this.ownQuestId,
  });

  @override
  PublicCoursePreviewController createState() =>
      PublicCoursePreviewController();
}

class PublicCoursePreviewController extends State<PublicCoursePreview>
    with CoursePlanProvider {
  RoomSummaryResponse? roomSummary;
  Object? roomSummaryError;
  bool loadingRoomSummary = false;

  /// The summary loaded but names no course — no room behind the link, or a
  /// room with no course plan. A known state ("Course not found"), unlike a
  /// summary request that failed outright (#380).
  bool courseNotFound = false;

  /// The preview modules list's outline loader (#7826). Created lazily — the
  /// quest id arrives with the room summary.
  QuestObjectivesLoader? _objectivesLoader;

  QuestObjectivesLoader get objectivesProvider => _objectivesLoader ??=
      QuestObjectivesLoader(client: Matrix.of(context).client);

  /// From this level a learner sent here from Start my own may still create
  /// their own course on the quest they picked (#9590).
  static const int _ownCourseMinLevel = 10;

  /// The picked quest, once the learner may create their own course on it.
  CoursePlanModel? _ownQuest;

  @override
  initState() {
    super.initState();
    _loadSummary();
    _loadOwnQuest();
  }

  @override
  void didUpdateWidget(covariant PublicCoursePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.roomID != oldWidget.roomID) {
      final oldRoomID = oldWidget.roomID;
      if (oldRoomID != null) CoursePreviewPlans.clear(shortRoomId(oldRoomID));
      _loadSummary();
    }
    if (widget.ownQuestId != oldWidget.ownQuestId) {
      _ownQuest = null;
      _loadOwnQuest();
    }
  }

  @override
  void dispose() {
    final roomID = widget.roomID;
    if (roomID != null) CoursePreviewPlans.clear(shortRoomId(roomID));
    _objectivesLoader?.dispose();
    super.dispose();
  }

  /// world_v2: the public course preview is route-driven
  /// (`/courses/preview/:courseroomid`) because its parent `/courses…` segments
  /// render a blank `EmptyPage`. A plain auto-pop back surfaces that blank page
  /// (#7400). The preview has a single entry mode — the browse-public list — so
  /// back returns to that list (`addcourse:browse`) over the world map, mirroring
  /// the route-driven course-detail fix (#7092).
  void back() {
    context.go(
      WorkspaceNav.openAddCoursePage(
        GoRouterState.of(context).uri,
        AddCourseSubpageEnum.browse,
      ),
    );
  }

  bool get loading => loadingCourse || loadingRoomSummary;
  bool get hasError =>
      (courseError != null || (!loadingCourse && course == null)) ||
      (roomSummaryError != null ||
          (!loadingRoomSummary && roomSummary == null));

  String get title {
    final course = this.course;
    final summary = roomSummary;
    final summaryDisplayName = summary?.displayName;
    if (summaryDisplayName != null) {
      return L10n.of(context).joinCourseWithTitle(summaryDisplayName);
    }

    if (course != null) {
      return L10n.of(context).joinCourseWithTitle(course.title);
    }

    return L10n.of(context).joinWithClassCode;
  }

  AddCourseTileContent? get content {
    final summary = roomSummary;
    final course = this.course;
    if (summary == null || course == null) return null;

    final avatarUrl = summary.avatarUrl;
    return CombinedAddCourseTileContent(
      title: summary.displayName ?? course.title,
      imageUrl: avatarUrl != null ? Uri.tryParse(avatarUrl) : null,
      members: summary.joinedMemberCount,
      courseId: summary.coursePlan?.uuid,
      isKnock: summary.joinRule == JoinRules.knock,
      expandedContent: course.description,
    );
  }

  Future<void> _loadSummary() async {
    try {
      final roomID = widget.roomID;
      if (roomID == null) {
        throw Exception("roomID is required");
      }

      setState(() {
        loadingRoomSummary = true;
        roomSummaryError = null;
        courseNotFound = false;
      });

      final roomIds = [fullRoomId(roomID)];
      final roomSummariesResponse = await Matrix.of(context).client
          .loadRoomSummaries(
            roomIds,
            l1Code: MatrixState.pangeaController.userController.userL1Code,
          );

      final roomSummary = roomSummariesResponse[fullRoomId(roomID)];
      if (roomSummary == null) {
        courseNotFound = true;
        throw Exception("Room summary not found");
      }

      this.roomSummary = roomSummary;
    } catch (e, s) {
      roomSummaryError = e;
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomID': widget.roomID, 'roomSummary': roomSummary?.toJson()},
        // A link to no course is a known state; a failed request is breakage.
        level: courseNotFound ? SentryLevel.warning : null,
      );
    } finally {
      if (mounted) {
        setState(() {
          loadingRoomSummary = false;
        });
      }
    }

    final planUuid = roomSummary?.coursePlan?.uuid;
    if (planUuid != null) {
      if (mounted) {
        // Scope the map to this course the moment the plan id is known — the
        // URL only carries the room id, so the page publishes the resolution
        // (#7826).
        CoursePreviewPlans.publish(shortRoomId(widget.roomID!), planUuid);
        objectivesProvider.loadOutline(planUuid);
      }
      await loadCourse(planUuid);
    } else {
      ErrorHandler.logError(
        e: Exception("No course plan found in room summary"),
        data: {'roomID': widget.roomID, 'roomSummary': roomSummary?.toJson()},
        level: roomSummaryError == null ? SentryLevel.warning : null,
      );
      if (mounted) {
        setState(() {
          // A summary that loaded but carries no plan is a link to no course;
          // a failed summary request stays the generic error.
          if (roomSummaryError == null) courseNotFound = true;
          // loadCourse never runs on this path, so its loading flag would
          // otherwise hold the page on an endless spinner (#380).
          loadingCourse = false;
          roomSummaryError = Exception("No course plan found in room summary");
        });
      }
    }
  }

  Future<void> _loadOwnQuest() async {
    final questId = widget.ownQuestId;
    if (questId == null) return;
    final analytics = Matrix.of(context).analyticsDataService;
    try {
      final quest = await QuestPlansRepo.get(questId);
      if (quest == null) {
        throw Exception('Picked quest did not load for Create my own course');
      }
      final stats = await analytics.derivedData(
        quest.targetLanguage.split('-').first,
      );
      if (!mounted || widget.ownQuestId != questId) return;
      if (stats.level < _ownCourseMinLevel) return;
      setState(() => _ownQuest = quest);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'quest_id': questId, 'roomID': widget.roomID},
        level: SentryLevel.warning,
      );
    }
  }

  Future<void> joinWithCode(String code) async {
    if (code.isEmpty) {
      return;
    }

    final client = Matrix.of(context).client;
    final result = await SpaceCodeController.joinSpaceWithCode(
      code,
      context: context,
      client: client,
    );
    final joinResp = result.result;
    if (joinResp == null) return;

    await SpaceCodeController.navigateAfterJoin(context, client, joinResp);
  }

  Future<void> joinCourse() async {
    if (widget.roomID == null) {
      throw Exception("roomID is required");
    }

    final roomID = widget.roomID;

    final client = Matrix.of(context).client;
    final r = client.getRoomById(roomID!);
    if (r != null && r.membership == Membership.join) {
      if (mounted) {
        context.go(
          WorkspaceNav.openCourse(GoRouterState.of(context).uri, r.id),
        );
      }
      return;
    }

    final knock = roomSummary?.joinRule == JoinRules.knock;
    if (knock) {
      final knockResult = await showFutureLoadingDialog(
        context: context,
        future: () async {
          try {
            return await client.knockAndRecordRoom(widget.roomID!);
          } catch (e, s) {
            ErrorHandler.logError(e: e, s: s, data: {'roomID': widget.roomID});
            rethrow;
          }
        },
      );
      // Only confirm the knock when it actually reached the server. On failure
      // the loading dialog has already surfaced the error; show "You have
      // knocked" only on success so it can't report a knock that never landed.
      if (knockResult.result == null) return;
      await showOkAlertDialog(
        context: context,
        title: L10n.of(context).youHaveKnocked,
        message: L10n.of(context).knockDesc,
      );
      return;
    }

    final accessCheckResp = await showFutureLoadingDialog<JoinResponse>(
      context: context,
      future: () => client.joinRoomWithAccessCheck(widget.roomID!),
    );
    final joinResp = accessCheckResp.result;
    if (joinResp == null) return;

    final room = client.getRoomById(joinResp.roomId);
    if (room == null) return;

    final handler = JoinRoomAnalyticsAccessHandler(joinResp, room);
    final joinedRoomId = await handler.handle(context);
    if (!mounted) return;

    context.go(
      WorkspaceNav.openCourse(GoRouterState.of(context).uri, joinedRoomId),
    );
  }

  @override
  Widget build(BuildContext context) => SelectedCourseView(
    closeButton: widget.closeButton,
    title: title,
    summary: roomSummary,
    course: course,
    content: content,
    loading: loading,
    hasError: hasError,
    unavailableMessage: courseNotFound
        ? L10n.of(context).courseNotFound
        : courseError is MissingQuestException
        ? L10n.of(context).missingCourseOutline
        : null,
    onTapCta: joinCourse,
    ctaButtonText: roomSummary?.joinRule == JoinRules.knock
        ? L10n.of(context).knock
        : L10n.of(context).join,
    ctaAlternative: _ownQuest == null
        ? null
        : CourseCtaAction(
            label: L10n.of(context).createMyOwnCourse,
            onPressed: () =>
                SelectedCourseController.launchCourse(context, _ownQuest!),
          ),
    objectivesProvider: _objectivesLoader,
  );
}
