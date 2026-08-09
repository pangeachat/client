import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/choice_cards/game_choice_card.dart';

/// Choice card for meaning analytics practice exercises with emoji, and alt text on flip
class GrammarChoiceCard extends StatelessWidget {
  final String choiceId;
  final String targetId;

  final MorphFeaturesEnum feature;
  final String tag;

  final VoidCallback onPressed;
  final bool isCorrect;
  final double height;
  final bool enabled;

  const GrammarChoiceCard({
    required this.choiceId,
    required this.targetId,
    required this.feature,
    required this.tag,
    required this.onPressed,
    required this.isCorrect,
    this.height = 72.0,
    this.enabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final baseTextSize =
        (Theme.of(context).textTheme.titleMedium?.fontSize ?? 16) *
        (height / 72.0).clamp(1.0, 1.4);
    final emojiSize = baseTextSize * 1.5;
    final copy =
        GrammarConstructsProvider.getTagTitle(
          feature: feature.name,
          tag: tag,
        ) ??
        tag;

    return GameChoiceCard(
      shouldFlip: false,
      targetId: targetId,
      onPressed: onPressed,
      isCorrect: isCorrect,
      height: height,
      isEnabled: enabled,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: height,
            height: height,
            child: Center(
              child: MorphIcon(
                feature: feature,
                tag: tag,
                size: Size(emojiSize, emojiSize),
              ),
            ),
          ),
          Expanded(
            child: Text(
              copy,
              overflow: TextOverflow.ellipsis,
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
