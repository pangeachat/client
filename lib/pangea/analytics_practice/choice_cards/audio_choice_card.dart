import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_practice/choice_cards/game_choice_card.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_widget.dart';

/// Choice card for audio activity with phonetic transcription above the word
class AudioChoiceCard extends StatelessWidget {
  final String choiceId;
  final String targetId;
  final String displayText;
  final LanguageModel textLanguage;
  final VoidCallback onPressed;
  final bool isCorrect;
  final bool isEnabled;
  final bool showHint;

  const AudioChoiceCard({
    required this.choiceId,
    required this.targetId,
    required this.displayText,
    required this.textLanguage,
    required this.onPressed,
    required this.isCorrect,
    this.isEnabled = true,
    this.showHint = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GameChoiceCard(
      shouldFlip: false,
      targetId: targetId,
      onPressed: onPressed,
      isCorrect: isCorrect,
      isEnabled: isEnabled,
      shrinkWrap: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHint)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhoneticTranscriptionWidget(
                  text: displayText,
                  pos: 'other',
                  textLanguage: textLanguage,
                  textOnly: true,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.7,
                    ),
                    fontSize: 14,
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 4),
              ],
            ),
          // Main word text
          Text(
            displayText,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
