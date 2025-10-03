import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_dialog.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_request.dart';

class TokenInfoFeedbackButton extends StatelessWidget {
  final TokenInfoFeedbackRequestData requestData;

  const TokenInfoFeedbackButton({
    super.key,
    required this.requestData,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.flag_outlined),
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => TokenInfoFeedbackDialog(
            requestData: requestData,
          ),
        );
      },
      tooltip: L10n.of(context).reportWordIssueTooltip,
    );
  }
}
