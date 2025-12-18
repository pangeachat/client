import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_dialog.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_notification.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_request.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TokenFeedbackUtil {
  static Future<void> showTokenFeedbackDialog(
    BuildContext context, {
    required TokenInfoFeedbackRequestData requestData,
    required String langCode,
    PangeaMessageEvent? event,
  }) async {
    final resp = await showDialog(
      context: context,
      builder: (context) => TokenInfoFeedbackDialog(
        requestData: requestData,
        langCode: langCode,
        event: event,
      ),
    );

    if (resp != null && resp is String) {
      OverlayUtil.showOverlay(
        overlayKey: "token_feedback_snackbar",
        context: context,
        child: TokenFeedbackNotification(message: resp),
        transformTargetId: '',
        position: OverlayPositionEnum.top,
        backDropToDismiss: false,
        closePrevOverlay: false,
        canPop: false,
      );

      Future.delayed(const Duration(seconds: 10), () {
        MatrixState.pAnyState.closeOverlay("token_feedback_snackbar");
      });
    }
  }
}
