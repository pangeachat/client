import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/pangea/analytics_access/join_room_analytics_consent_handler.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/course_creation/public_course_preview_view.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_builder.dart';
import 'package:fluffychat/pangea/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/pangea/join_codes/space_code_controller.dart';
import 'package:fluffychat/pangea/room_summaries/room_summaries_repo.dart';
import 'package:fluffychat/pangea/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PublicCoursePreview extends StatefulWidget {
  final String? roomID;

  const PublicCoursePreview({super.key, required this.roomID});

  @override
  PublicCoursePreviewController createState() =>
      PublicCoursePreviewController();
}

class PublicCoursePreviewController extends State<PublicCoursePreview>
    with CoursePlanProvider {
  RoomSummaryResponse? roomSummary;
  Object? roomSummaryError;
  bool loadingRoomSummary = false;

  @override
  initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void didUpdateWidget(covariant PublicCoursePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.roomID != oldWidget.roomID) {
      _loadSummary();
    }
  }

  bool get loading => loadingCourse || loadingRoomSummary;
  bool get hasError =>
      (courseError != null || (!loadingCourse && course == null)) ||
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

      final roomIds = [roomID];
      final roomSummariesRepo = RoomSummariesRepo(Matrix.of(context).client);
      final roomSummariesResponse = await roomSummariesRepo.loadRoomSummaries(
        roomIds,
      );

      final roomSummary = roomSummariesResponse[roomID];
      if (roomSummary == null) {
        throw Exception("Room summary not found");
      }

      this.roomSummary = roomSummary;
    } catch (e, s) {
      roomSummaryError = e;
      loadingCourse = false;

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
      await loadCourse(roomSummary!.coursePlan!.uuid).then((_) => loadTopics());
    } else {
      ErrorHandler.logError(
        e: Exception("No course plan found in room summary"),
        data: {'roomID': widget.roomID, 'roomSummary': roomSummary?.toJson()},
      );
      if (mounted) {
        setState(() {
          roomSummaryError = Exception("No course plan found in room summary");
          loadingCourse = false;
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

    final room = client.getRoomById(joinResp.roomId);
    if (room == null) return;

    final handler = JoinRoomAnalyticsConsentHandler(joinResp, room);
    final joinedRoomId = await handler.handle(context);
    if (joinedRoomId == null) return;

    room.isSpace
        ? context.go('/rooms/spaces/$joinedRoomId/details')
        : context.go('/rooms/$joinedRoomId');
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
        context.go("/rooms/spaces/${r.id}/details");
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

    context.go("/rooms/spaces/$joinedRoomId/details");
  }

  @override
  Widget build(BuildContext context) => PublicCoursePreviewView(this);
}
