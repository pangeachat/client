import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_practice/choice_cards/game_choice_card.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';

/// Choice card for meaning activity with emoji, and alt text on flip
class MeaningChoiceCard extends StatelessWidget {
  final String choiceId;
  final String targetId;
  final String displayText;
  final String? emoji;
  final VoidCallback onPressed;
  final bool isCorrect;
  final double height;
  final bool isEnabled;

  const MeaningChoiceCard({
    required this.choiceId,
    required this.targetId,
    required this.displayText,
    this.emoji,
    required this.onPressed,
    required this.isCorrect,
    this.height = 72.0,
    this.isEnabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final baseTextSize =
        (Theme.of(context).textTheme.titleMedium?.fontSize ?? 16) *
            (height / 72.0).clamp(1.0, 1.4);
    final emojiSize = baseTextSize * 1.2;

    return GameChoiceCard(
      shouldFlip: true,
      targetId: targetId,
      onPressed: onPressed,
      isCorrect: isCorrect,
      height: height,
      isEnabled: isEnabled,
      altChild: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (emoji != null && emoji!.isNotEmpty)
            SizedBox(
              width: height * .7,
              height: height,
              child: Center(
                child: Text(
                  emoji!,
                  style: TextStyle(fontSize: emojiSize),
                ),
              ),
            ),
          Expanded(
            child: Text(
              ConstructIdentifier.fromString(choiceId)!.lemma,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: baseTextSize,
              ),
            ),
          ),
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
                child: Text(
                  emoji!,
                  style: TextStyle(fontSize: emojiSize),
                ),
              ),
            ),
          Expanded(
            child: Text(
              displayText,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: baseTextSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
