import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/features/tutorials/tutorial_copy.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_word_bubble.dart';

class TutorialTooltipWidget extends StatelessWidget {
  final String text;
  final int currentStep;
  final int totalSteps;

  /// A branch step's answers. Rendered inside the card, below the progress row,
  /// so the card grows to contain them — floating them over its bottom edge left
  /// them straddling the border and covering the progress bar.
  final List<({String label, TutorialChoiceOutcome outcome})> choices;
  final void Function(TutorialChoiceOutcome)? onChoice;

  /// The L2 greeting, shown as a tappable vocabulary word above [text].
  final TutorialGreeting? wordBubble;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final TextStyle? textStyle;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const TutorialTooltipWidget({
    required this.text,
    required this.currentStep,
    required this.totalSteps,
    this.choices = const [],
    this.onChoice,
    this.wordBubble,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.textStyle,
    this.iconSize = 32.0,
    this.backgroundColor,
    this.foregroundColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final background = backgroundColor ?? theme.cardColor;

    final style = textStyle ?? theme.textTheme.bodyMedium;

    final progress = totalSteps > 0 ? currentStep / totalSteps : 0.0;

    return Container(
      padding: padding,
      // decoration: BoxDecoration(color: background, borderRadius: borderRadius),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(width: 2, color: theme.colorScheme.primary),
        borderRadius: const BorderRadius.all(Radius.circular(12.0)),
      ),
      child: Column(
        children: [
          // The greeting and the message are ONE vertically centered block, so
          // the slack above and below it is equal. Held apart before — the
          // greeting a fixed-height child at the top, the message given all the
          // slack — every spare pixel pooled under the greeting: it sat tight
          // against the card's top edge with a gap beneath it.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Above the bot-face row rather than inside it: sharing
                        // the row centered the greeting on the text column
                        // instead of the card, reading as offset to the right.
                        if (wordBubble != null) ...[
                          _TutorialGreeting(greeting: wordBubble!),
                          const SizedBox(height: 8.0),
                        ],
                        Row(
                          spacing: 8.0,
                          children: [
                            BotFace(
                              width: iconSize,
                              expression: BotExpression.gold,
                            ),
                            Expanded(
                              child: Text(
                                text,
                                style: style,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(4.0),
            child: Row(
              children: [
                Text(
                  "$currentStep / $totalSteps",
                  style: theme.textTheme.labelSmall,
                ),
                SizedBox(width: 8.0),
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8.0,
                    borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                    color: progress >= 1.0 ? AppConfig.success : null,
                  ),
                ),
              ],
            ),
          ),
          if (choices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                spacing: 8.0,
                children: [
                  for (final choice in choices)
                    Expanded(
                      child: _TutorialChoiceButton(
                        label: choice.label,
                        // The app's colour hierarchy: one darker filled primary
                        // leads, and anything following it is a fully filled but
                        // lighter primaryContainer button.
                        secondary:
                            choice.outcome != TutorialChoiceOutcome.advance,
                        onPressed: () => onChoice?.call(choice.outcome),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TutorialChoiceButton extends StatelessWidget {
  final String label;
  final bool secondary;
  final VoidCallback onPressed;

  const _TutorialChoiceButton({
    required this.label,
    required this.secondary,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: secondary ? scheme.primaryContainer : scheme.primary,
        foregroundColor: secondary
            ? scheme.onPrimaryContainer
            : scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// The step's L2 greeting, displayed large and centered across the full width
/// of the card, above everything else. Why it stands on its own line rather
/// than inside the sentence belongs to the step's copy — see the welcome entry
/// in the step templates.
class _TutorialGreeting extends StatelessWidget {
  final TutorialGreeting greeting;

  const _TutorialGreeting({required this.greeting});

  @override
  Widget build(BuildContext context) {
    // Display size, not body size: the greeting IS the step's subject, and at
    // the sentence's size it read as an aside.
    final style = Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold);

    return SizedBox(
      width: double.infinity,
      child: Center(
        // Shown either way. Only a resolved L2 word is a tappable vocabulary
        // bubble; the fallbacks still greet the learner, just in a language they
        // already speak and with nothing to look up. The sentence no longer
        // carries the greeting, so dropping it here would leave the step with no
        // greeting at all.
        child: greeting.isBubble
            ? TutorialWordBubble(greeting: greeting, style: style)
            : Text(greeting.word, style: style, textAlign: TextAlign.center),
      ),
    );
  }
}
