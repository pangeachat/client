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

  /// A word in [text] to draw as a tappable vocabulary word instead of as text.
  /// Its position comes from [TutorialCopy.wordSlot] in the copy.
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
          Expanded(
            child: Row(
              spacing: 8.0,
              children: [
                BotFace(width: iconSize, expression: BotExpression.gold),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(
                            child: _TutorialTooltipText(
                              text: text,
                              style: style,
                              wordBubble: wordBubble,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
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

/// The card's copy, with one word optionally drawn as a vocabulary bubble.
///
/// The copy stays a single localized string: the host substitutes
/// [TutorialCopy.wordSlot] where the word goes and this splits on it, so the
/// bubble lands wherever the translator put the placeholder rather than where
/// English happens to put it.
class _TutorialTooltipText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TutorialGreeting? wordBubble;

  const _TutorialTooltipText({
    required this.text,
    required this.style,
    required this.wordBubble,
  });

  @override
  Widget build(BuildContext context) {
    final bubble = wordBubble;
    final split = TutorialCopy.splitOnWordSlot(text);
    if (bubble == null || !bubble.isBubble || split == null) {
      // Any leftover marker becomes the word itself rather than being shown, so
      // copy resolved for a bubble still reads correctly when the bubble could
      // not be built.
      return Text(
        text.replaceAll(TutorialCopy.wordSlot, bubble?.word ?? ''),
        style: style,
        textAlign: TextAlign.center,
      );
    }

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (split.before.isNotEmpty) TextSpan(text: split.before),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: TutorialWordBubble(greeting: bubble, style: style),
          ),
          if (split.after.isNotEmpty) TextSpan(text: split.after),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
