import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';

/// An XP figure in the activity's own XP look (#9559): the sparkle the goal
/// header shows beside a session's XP, then [text] in the theme's text gold —
/// so a finished session's XP reads as the same thing the learner watched
/// grow in the session. [semanticsLabel] is what a screen reader hears.
class SparkleXpText extends StatelessWidget {
  final String text;
  final String semanticsLabel;

  const SparkleXpText({
    required this.text,
    required this.semanticsLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 3.0,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 14.0,
              color: theme.pangea.goldGraphic,
            ),
            Text(
              text,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.pangea.gold,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
