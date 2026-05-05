import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

class JoinRoomAnalyticsConsentHandler {
  final JoinResponse? joinResponse;
  const JoinRoomAnalyticsConsentHandler(this.joinResponse);

  Future<String?> handle(BuildContext context) async {
    final resp = joinResponse;
    if (resp == null) return null;
    if (resp.shouldShowAnalyticsAccessNotice) {
      await _showAccessDialog(context);
    }
    return resp.roomId;
  }

  Future<void> _showAccessDialog(BuildContext context) => showOkAlertDialog(
    context: context,
    title: "Analytics Access Required",
    message:
        "By joining this course, you agree to grant admins access to your learning analytics.",
  );
}
