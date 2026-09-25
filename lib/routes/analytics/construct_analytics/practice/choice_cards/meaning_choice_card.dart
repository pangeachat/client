import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/pangea/common/widgets/language_semantics.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/choice_cards/game_choice_card.dart';

/// Choice card for meaning analytics practice exercises with emoji, and alt text on flip
class MeaningChoiceCard extends StatelessWidget {
  final String choiceId;
  final String targetId;
  final String displayText;
  final String? emoji;

  /// The lemma's language, marked on the lemma shown once the card flips.
  final String? langCode;
  final VoidCallback onPressed;
  final bool isCorrect;
  final double height;
  final bool isEnabled;
  final bool isSelected;

  const MeaningChoiceCard({
    required this.choiceId,
    required this.targetId,
    required this.displayText,
    this.emoji,
    this.langCode,
    required this.onPressed,
    required this.isCorrect,
    this.height = 72.0,
    this.isEnabled = true,
    this.isSelected = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final baseTextSize =
        (Theme.of(context).textTheme.titleMedium?.fontSize ?? 16) *
        (height / 72.0).clamp(1.0, 1.4);
    final emojiSize = baseTextSize * 1.2;
    final lemma = ConstructIdentifier.fromString(choiceId)!.lemma;

    return GameChoiceCard(
      shouldFlip: true,
      targetId: targetId,
      onPressed: onPressed,
      isCorrect: isCorrect,
      height: height,
      isEnabled: isEnabled,
      isSelected: isSelected,
      altChild: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (emoji != null && emoji!.isNotEmpty)
            SizedBox(
              width: height * .7,
              height: height,
              child: Center(
                child: Text(emoji!, style: TextStyle(fontSize: emojiSize)),
              ),
            ),
          Expanded(
            // Merges into the card's one name beside the emoji, so the lemma
            // is marked by range rather than as a node of its own (#9266).
            child: Semantics(
              attributedLabel: LanguageSemantics.labelWithPart(
                lemma,
                part: lemma,
                langCode: langCode,
              ),
              excludeSemantics: true,
              child: Text(
                lemma,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                textAlign: TextAlign.left,
                style: TextStyle(fontSize: baseTextSize),
              ),
            ),
          ),
          SizedBox(width: 8.0),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (emoji != null && emoji!.isNotEmpty)
            SizedBox(
              width: height * .7,
              height: height,
              child: Center(
                child: Text(emoji!, style: TextStyle(fontSize: emojiSize)),
              ),
            ),
          Expanded(
            child: Text(
              displayText,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: baseTextSize),
            ),
          ),
          SizedBox(width: 8.0),
        ],
      ),
    );
  }
}
