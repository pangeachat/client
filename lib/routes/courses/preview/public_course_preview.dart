import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_consent_handler.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/features/join_codes/space_code_controller.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/courses/preview/public_course_preview_view.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PublicCoursePreview extends StatefulWidget {
  final String? roomID;
  final Widget? closeButton;

  const PublicCoursePreview({
    super.key,
    required this.roomID,
    this.closeButton,
  });

  @override
  PublicCoursePreviewController createState() =>
      PublicCoursePreviewController();
}

class PublicCoursePreviewController extends State<PublicCoursePreview> {
  RoomSummaryResponse? roomSummary;
  Object? roomSummaryError;
  bool loadingRoomSummary = false;

  late final QuestObjectivesLoader _objectivesProvider;

  @override
  initState() {
    super.initState();
    _objectivesProvider = QuestObjectivesLoader(
      client: Matrix.of(context).client,
    );
    _loadSummary();
  }

  @override
  void didUpdateWidget(covariant PublicCoursePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.roomID != oldWidget.roomID) {
      _loadSummary();
    }
  }

  @override
  void dispose() {
    _objectivesProvider.dispose();
    super.dispose();
  }

  QuestObjectivesLoader get objectivesProvider => _objectivesProvider;

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

  bool get _loadingCourse =>
      _objectivesProvider.questLoader.value is AsyncLoading;

  Object? get _courseError => switch (_objectivesProvider.questLoader.value) {
    AsyncError(error: final error) => error,
    _ => null,
  };

  QuestPlan? get course => switch (_objectivesProvider.questLoader.value) {
    AsyncLoaded(value: final value) => value.quest,
    _ => null,
  };

  bool get loading => _loadingCourse || loadingRoomSummary;
  bool get hasError =>
      (_courseError != null || (!_loadingCourse && course == null)) ||
      (roomSummaryError != null ||
          (!loadingRoomSummary && roomSummary == null));

  Future<void> _loadSummary() async {
    try {
      final roomID = widget.roomID;
      if (roomID == null) {
        throw Exception("roomID is required");
      }

      setState(() {
        loadingRoomSummary = true;
        roomSummaryError = null;
      });

      final roomIds = [fullRoomId(roomID)];
      final roomSummariesResponse = await Matrix.of(context).client
          .loadRoomSummaries(
            roomIds,
            l1Code: MatrixState.pangeaController.userController.userL1Code,
          );

      final roomSummary = roomSummariesResponse[fullRoomId(roomID)];
      if (roomSummary == null) {
        throw Exception("Room summary not found");
      }

      this.roomSummary = roomSummary;
    } catch (e, s) {
      roomSummaryError = e;
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomID': widget.roomID, 'roomSummary': roomSummary?.toJson()},
      );
    } finally {
      if (mounted) {
        setState(() {
          loadingRoomSummary = false;
        });
      }
    }

    if (roomSummary?.coursePlan != null) {
      await _objectivesProvider.loadOutline(roomSummary!.coursePlan!.uuid);
    } else {
      ErrorHandler.logError(
        e: Exception("No course plan found in room summary"),
        data: {'roomID': widget.roomID, 'roomSummary': roomSummary?.toJson()},
      );
      if (mounted) {
        setState(() {
          roomSummaryError = Exception("No course plan found in room summary");
        });
      }
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
      await showFutureLoadingDialog(
        context: context,
        future: () async {
          try {
            await client.knockAndRecordRoom(widget.roomID!);
          } catch (e, s) {
            ErrorHandler.logError(e: e, s: s, data: {'roomID': widget.roomID});
            rethrow;
          }
        },
      );
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

    final handler = JoinRoomAnalyticsConsentHandler(joinResp, room);
    final joinedRoomId = await handler.handle(context);
    if (joinedRoomId == null) {
      ErrorHandler.logError(
        e: Exception("Failed to fetch roomID in public course preview"),
        data: {'roomID': widget.roomID},
      );
      throw Exception("Failed to fetch roomID");
    }

    context.go(
      WorkspaceNav.openCourse(GoRouterState.of(context).uri, joinedRoomId),
    );
  }

  @override
  Widget build(BuildContext context) => PublicCoursePreviewView(this);
}
