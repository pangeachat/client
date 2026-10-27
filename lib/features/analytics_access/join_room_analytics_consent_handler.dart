import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/access_notice_extension.dart';
import 'package:fluffychat/features/analytics_access/analytics_access_notice_dialog.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

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
}
