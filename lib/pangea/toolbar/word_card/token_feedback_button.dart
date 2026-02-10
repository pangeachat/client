import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/lemmas/lemma_meaning_builder.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_builder.dart';
import 'package:fluffychat/pangea/phonetic_transcription/pt_v2_models.dart';

class TokenFeedbackButton extends StatelessWidget {
  final LanguageModel textLanguage;
  final ConstructIdentifier constructId;
  final String text;

  final Function(LemmaInfoResponse, PTRequest, PTResponse) onFlagTokenInfo;
  final Map<String, dynamic> messageInfo;

  const TokenFeedbackButton({
    super.key,
    required this.textLanguage,
    required this.constructId,
    required this.text,
    required this.onFlagTokenInfo,
    required this.messageInfo,
  });

  @override
  Widget build(BuildContext context) {
    return LemmaMeaningBuilder(
      langCode: textLanguage.langCode,
      constructId: constructId,
      messageInfo: messageInfo,
      builder: (context, lemmaController) {
        return PhoneticTranscriptionBuilder(
          textLanguage: textLanguage,
          text: text,
          builder: (context, transcriptController) {
            final enabled =
                (lemmaController.lemmaInfo != null ||
                    lemmaController.isError) &&
                (transcriptController.ptResponse != null ||
                    transcriptController.isError);

            final lemmaInfo =
                lemmaController.lemmaInfo ?? LemmaInfoResponse.error;

            return IconButton(
              color: Theme.of(context).iconTheme.color,
              icon: const Icon(Icons.flag_outlined),
              onPressed: enabled && transcriptController.ptResponse != null
                  ? () {
                      onFlagTokenInfo(
                        lemmaInfo,
                        transcriptController.ptRequest,
                        transcriptController.ptResponse!,
                      );
                    }
                  : null,
              tooltip: enabled ? L10n.of(context).reportWordIssueTooltip : null,
            );
          },
        );
      },
    );
  }
}
