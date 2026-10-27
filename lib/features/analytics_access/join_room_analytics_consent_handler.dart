import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/access_notice_extension.dart';
import 'package:fluffychat/features/analytics_access/analytics_access_notice_dialog.dart';
import 'package:fluffychat/features/analytics_access/course_settings_model.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';

class JoinRoomAnalyticsConsentHandler {
  final JoinResponse joinResponse;
  final Room room;

  const JoinRoomAnalyticsConsentHandler(this.joinResponse, this.room);

  /// The run in progress for each course. More than one caller can reach the
  /// same course at once — a class-link join alongside the chat list's
  /// pending-notice check, or the link page submitting twice — and each used
  /// to stack its own notice. Answering Go back on one and Share and join on
  /// the other granted for a course the learner had just left (CLIENT-EFF), so
  /// later callers share the first run's notice and answer instead.
  static final Map<String, Future<String?>> _inFlight = {};

  /// Show the user access consent dialog (if not already shown for this course),
  /// leaves room and return null if rejected, grants access and return roomId if accepted
  Future<String?> handle(BuildContext context) async {
    // A teacher claiming their course is not joining as a learner. Do not
    // record learner consent or grant access to their personal analytics.
    if (room.isRoomAdmin) return room.id;

    final roomId = room.id;
    // A block body: `remove` returns this very future, and whenComplete
    // waits on a returned future, so an arrow body would never complete.
    return _inFlight[roomId] ??= _handle(context).whenComplete(() {
      _inFlight.remove(roomId);
    });
  }

  Future<String?> _handle(BuildContext context) async {
    final roomId = room.id;
    final client = room.client;

    if (!client.acceptedAccessNotice(roomId)) {
      await client.setAccessNoticePending(roomId);
    }

    final acceptedAccessRequest = await _showNotice(context);
    if (!acceptedAccessRequest) {
      return null;
    }

    await client.setAccessNoticeAccepted(roomId);
    await _grantAccess();
    return roomId;
  }

  /// Returns false if user was shown the dialog and rejected it, meaning they left the room
  Future<bool> _showNotice(BuildContext context) async {
    if (!joinResponse.shouldShowNotice) {
      return true;
    }

    // A learner who already shares with this course is not asked; accepting
    // for them grants the teachers who cannot see yet
    // (course-analytics-access.instructions.md, "Don't ask a student who
    // already shares").
    if (await room.client.sharesAnalyticsWithCourse(room)) {
      return true;
    }

    final targetLanguage = await room.client.getCourseLanguage(room);
    final noticeResp = await showDialog<OkCancelResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          AnalyticsAccessNoticeDialog(targetLanguage: targetLanguage),
    );

    if (noticeResp != OkCancelResult.cancel) {
      return true;
    }

    await room.leave();
    return false;
  }

  Future<void> _grantAccess() =>
      room.client.grantInstructorsAnalyticsAccess(joinResponse.roomId);

  /// Every join caller runs [handle] on the local room, so a join that outran
  /// sync skipped it and recorded no answer at all
  /// (course-analytics-access.instructions.md, "A slow join still asks").
  /// Reads the course's requirement over HTTP; when it is on, marks the course
  /// pending — the chat list asks pending courses when it opens — and asks as
  /// soon as the room lands, sending a learner who goes back to the map.
  static Future<void> askOnceSynced(
    Client client,
    String roomId, {
    @visibleForTesting BuildContext? Function()? navigatorContext,
  }) async {
    try {
      final Map<String, Object?> settings;
      try {
        settings = await client.getRoomStateWithKey(
          roomId,
          PangeaEventTypes.courseSettings,
          '',
        );
      } on MatrixException catch (e) {
        // silent-ok: no settings event, so nothing here requires sharing
        if (e.error == MatrixError.M_NOT_FOUND) return;
        rethrow;
      }
      if (!CourseSettingsModel.fromJson(settings).requireAnalyticsAccess) {
        return;
      }

      if (!client.acceptedAccessNotice(roomId)) {
        await client.setAccessNoticePending(roomId);
      }

      // Any later sync, not one naming the room: it may land before this
      // listens, and would not be named again.
      Room? joinedRoom() {
        final room = client.getRoomById(roomId);
        return room?.membership == Membership.join ? room : null;
      }

      if (joinedRoom() == null) {
        await client.onSync.stream.firstWhere((_) => joinedRoom() != null);
      }
      final room = joinedRoom()!;

      // No screen to ask on: the pending mark asks on the next visit.
      final context = (navigatorContext ?? _appNavigatorContext)();
      if (context == null || !context.mounted) return;

      final joinedRoomId = await JoinRoomAnalyticsConsentHandler(
        JoinResponse(
          roomId: roomId,
          shouldShowNotice: room.shouldShowAnalyticsAccessNotice,
        ),
        room,
      ).handle(context);
      if (joinedRoomId == null && context.mounted) {
        GoRouter.maybeOf(context)?.go(WorkspaceNav.clearAll());
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"joining_room_id": roomId},
        level: PangeaHttpException.severityOf(e),
      );
    }
  }

  static BuildContext? _appNavigatorContext() =>
      FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
}
