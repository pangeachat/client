import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_dialog.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_request.dart';

class TokenInfoFeedbackButton extends StatelessWidget {
  final TokenInfoFeedbackRequestData requestData;
  final String langCode;

  const TokenInfoFeedbackButton({
    super.key,
    required this.requestData,
    required this.langCode,
  });

  Future<void> _submitFeedback(BuildContext context) async {
    final resp = await showDialog(
      context: context,
      builder: (context) => TokenInfoFeedbackDialog(
        requestData: requestData,
        langCode: langCode,
      ),
    );

    if (resp != null && resp is String) {
      _showSuccessSnackBar(resp, context);
    }
  }

  void _showSuccessSnackBar(String message, BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const BotFace(
              width: 30,
              expression: BotExpression.idle,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
        duration: const Duration(seconds: 30),
        action: SnackBarAction(
          label: L10n.of(context).close,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.flag_outlined),
      onPressed: () => _submitFeedback(context),
      tooltip: L10n.of(context).reportWordIssueTooltip,
    );
  }
}
