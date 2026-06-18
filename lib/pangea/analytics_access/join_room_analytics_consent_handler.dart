import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_access/access_notice_extension.dart';
import 'package:fluffychat/pangea/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

class JoinRoomAnalyticsConsentHandler {
  final JoinResponse joinResponse;
  final Room room;

  const JoinRoomAnalyticsConsentHandler(this.joinResponse, this.room);

  static String? _currentRoomId;

  static String? get currentRoomId => _currentRoomId;

  /// Show the user access consent dialog (if not already shown for this course),
  /// leaves room and return null if rejected, grants access and return roomId if accepted
  Future<String?> handle(BuildContext context) async {
    final roomId = room.id;
    final client = room.client;

    _currentRoomId = roomId;

    try {
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
    } catch (e) {
      rethrow;
    } finally {
      _currentRoomId = null;
    }
  }

  /// Returns false if user was shown the dialog and rejected it, meaning they left the room
  Future<bool> _showNotice(BuildContext context) async {
    if (!joinResponse.shouldShowNotice) {
      return true;
    }

    final noticeResp = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).analyticsAccessNoticeTitle,
      message: L10n.of(context).analyticsAccessNoticeDesc,
      barrierDismissible: false,
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
