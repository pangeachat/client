import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/lemmas/lemma_meaning_builder.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/phonetic_transcription_builder.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_models.dart';

class TokenFeedbackButton extends StatelessWidget {
  final LemmaMeaningBuilderState lemma;
  final PhoneticTranscriptionBuilderState transcription;
  final Function(LemmaInfoResponse, PTRequest, PTResponse) onFlagTokenInfo;

  const TokenFeedbackButton({
    super.key,
    required this.lemma,
    required this.transcription,
    required this.onFlagTokenInfo,
  });

  @override
  Widget build(BuildContext context) {
    final enabled =
        (lemma.lemmaInfo != null || lemma.isError) &&
        (transcription.ptResponse != null || transcription.isError);

    final lemmaInfo = lemma.lemmaInfo ?? LemmaInfoResponse.error;

    return IconButton(
      color: Theme.of(context).iconTheme.color,
      icon: const Icon(Icons.flag_outlined),
      onPressed: enabled && transcription.ptResponse != null
          ? () {
              onFlagTokenInfo(
                lemmaInfo,
                transcription.ptRequest,
                transcription.ptResponse!,
              );
            }
          : null,
      tooltip: enabled ? L10n.of(context).reportWordIssueTooltip : null,
    );
  }
}
