import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TokenInfoFeedbackButton extends StatelessWidget {
  final String roomId;
  final String fullText;
  final String detectedLanguage;
  final List<PangeaToken> tokens;
  final int selectedToken;
  final LemmaInfoResponse? lemmaInfo;
  final String? phonetics;
  final String wordCardL1;

  const TokenInfoFeedbackButton({
    super.key,
    required this.roomId,
    required this.fullText,
    required this.detectedLanguage,
    required this.tokens,
    required this.selectedToken,
    this.lemmaInfo,
    this.phonetics,
    required this.wordCardL1,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.flag_outlined),
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => TokenInfoFeedbackDialog(
            userId: Matrix.of(context).client.userID!,
            roomId: roomId,
            fullText: fullText,
            detectedLanguage: detectedLanguage,
            tokens: tokens,
            selectedToken: selectedToken,
            lemmaInfo: lemmaInfo,
            phonetics: phonetics,
            wordCardL1: wordCardL1,
          ),
        );
      },
      tooltip: L10n.of(context).reportWordIssueTooltip,
    );
  }
}
