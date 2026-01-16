import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_practice/choice_cards/game_choice_card.dart';
import 'package:fluffychat/pangea/common/widgets/word_audio_button.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Displays an audio button with a select label in a row layout
/// TODO: needs a better design and button handling
class AudioChoiceCard extends StatelessWidget {
  final String text;
  final String targetId;
  final VoidCallback onPressed;
  final bool isCorrect;
  final double height;
  final bool isEnabled;

  const AudioChoiceCard({
    required this.text,
    required this.targetId,
    required this.onPressed,
    required this.isCorrect,
    this.height = 72.0,
    this.isEnabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GameChoiceCard(
      shouldFlip: false,
      targetId: targetId,
      onPressed: onPressed,
      isCorrect: isCorrect,
      height: height,
      isEnabled: isEnabled,
      child: Row(
        children: [
          Expanded(
            child: WordAudioButton(
              text: text,
              uniqueID: "vocab_practice_choice_$text",
              langCode:
                  MatrixState.pangeaController.userController.userL2!.langCode,
            ),
          ),
          Text(L10n.of(context).select),
        ],
      ),
    );
  }
}
