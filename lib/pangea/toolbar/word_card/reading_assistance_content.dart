import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/model/message_types.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/phonetic_transcription/pt_v2_models.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_request.dart';
import 'package:fluffychat/pangea/toolbar/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/word_card/word_zoom_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';

const double minCardHeight = 70;

class ReadingAssistanceContent extends StatelessWidget {
  final MessageOverlayController overlayController;
  final Duration animationDuration;

  const ReadingAssistanceContent({
    super.key,
    required this.overlayController,
    this.animationDuration = FluffyThemes.animationDuration,
  });

  @override
  Widget build(BuildContext context) {
    if (![MessageTypes.Text, MessageTypes.Audio].contains(
      overlayController.pangeaMessageEvent.event.messageType,
    )) {
      return const SizedBox();
    }

    final tokens = overlayController.pangeaMessageEvent.originalSent?.tokens;
    final selectedToken = overlayController.selectedToken;
    final selectedTokenIndex = selectedToken != null
        ? tokens?.indexWhere(
              (t) => t.text == selectedToken.text,
            ) ??
            -1
        : -1;

    return WordZoomWidget(
      key: MatrixState.pAnyState
          .layerLinkAndKey(
            "word-zoom-card-${overlayController.selectedToken!.text.uniqueKey}",
          )
          .key,
      token: overlayController.selectedToken!.text,
      construct: overlayController.selectedToken!.vocabConstructID,
      pos: overlayController.selectedToken!.pos,
      morph: overlayController.selectedToken!.morph
          .map((k, v) => MapEntry(k.name, v)),
      event: overlayController.event,
      onClose: () => overlayController.updateSelectedSpan(null),
      langCode: overlayController.pangeaMessageEvent.messageDisplayLangCode,
      onDismissNewWordOverlay: () => overlayController.setState(() {}),
      onFlagTokenInfo: (LemmaInfoResponse lemmaInfo, PTRequest ptRequest, PTResponse ptResponse) {
        if (selectedTokenIndex < 0) return;
        final requestData = TokenInfoFeedbackRequestData(
          userId: Matrix.of(context).client.userID!,
          roomId: overlayController.event.room.id,
          fullText: overlayController.pangeaMessageEvent.messageDisplayText,
          detectedLanguage:
              overlayController.pangeaMessageEvent.messageDisplayLangCode,
          tokens: tokens ?? [],
          selectedToken: selectedTokenIndex,
          wordCardL1: MatrixState.pangeaController.userController.userL1Code!,
          lemmaInfo: lemmaInfo,
          ptRequest: ptRequest,
          ptResponse: ptResponse,
        );
        overlayController.widget.chatController.showTokenFeedbackDialog(
          requestData,
          overlayController.pangeaMessageEvent.messageDisplayLangCode,
          overlayController.pangeaMessageEvent,
        );
      },
    );
  }
}
