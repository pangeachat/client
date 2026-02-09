import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_response_dialog.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_dialog.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_request.dart';

class TokenFeedbackUtil {
  static Future<void> showTokenFeedbackDialog(
    BuildContext context, {
    required TokenInfoFeedbackRequestData requestData,
    required String langCode,
    PangeaMessageEvent? event,
    VoidCallback? onUpdated,
  }) async {
    final resp = await showDialog(
      context: context,
      builder: (context) => TokenInfoFeedbackDialog(
        requestData: requestData,
        langCode: langCode,
        event: event,
      ),
    );

    if (resp == null) return;

    onUpdated?.call();
    await showDialog(
      context: context,
      builder: (context) {
        return FeedbackResponseDialog(
          title: L10n.of(context).tokenInfoFeedbackDialogTitle,
          feedback: resp,
        );
      },
    );
  }
}
