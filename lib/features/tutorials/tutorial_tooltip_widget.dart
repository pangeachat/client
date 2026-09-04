import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/features/tutorials/tutorial_copy.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_word_bubble.dart';
import 'package:fluffychat/l10n/l10n.dart';

class TutorialTooltipWidget extends StatelessWidget {
  final String text;
  final int currentStep;
  final int totalSteps;

  /// Names the running sequence, under the progress bar, so back-to-back
  /// sequences read as different walkthroughs rather than one restarting.
  final String? sequenceTitle;

  /// Skips the whole sequence. Null hides the control.
  final VoidCallback? onSkip;

  /// A branch step's answers. Rendered inside the card, below the progress row,
  /// so the card grows to contain them — floating them over its bottom edge left
  /// them straddling the border and covering the progress bar.
  final List<({String label, TutorialChoiceOutcome outcome})> choices;
  final void Function(TutorialChoiceOutcome)? onChoice;

  /// The L2 greeting, shown as a tappable vocabulary word above [text].
  final TutorialGreeting? wordBubble;

  const TutorialTooltipWidget({
    required this.text,
    required this.currentStep,
    required this.totalSteps,
    this.sequenceTitle,
    this.onSkip,
    this.choices = const [],
    this.onChoice,
    this.wordBubble,
    super.key,
  });

  /// The bot face is the card's speaker; at the old 32px it read as an icon
  /// rather than a sender avatar.
  static const double _botFaceSize = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final style = theme.textTheme.bodyMedium;

    final progress = totalSteps > 0 ? currentStep / totalSteps : 0.0;

    return Container(
      padding: const EdgeInsets.all(8),
      // Styled like a message from the bot, not a generic tooltip: the same
      // surface and corner radius other-party chat bubbles use, no border.
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.all(
          Radius.circular(AppConfig.borderRadius),
        ),
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
                          // Top-aligned like a chat message: the avatar sits at
                          // the head of the text, not floating beside its middle.
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const BotFace(
                              width: _botFaceSize,
                              expression: BotExpression.gold,
                            ),
                            Expanded(
                              child: Text(
                                text,
                                style: style,
                                textAlign: TextAlign.start,
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
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
            child: Row(
              children: [
                Text(
                  "$currentStep / $totalSteps",
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8.0,
                    borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                    // Green from the first step: the bar reports progress made,
                    // and a color that only arrives at the end read as the
                    // earlier steps not counting.
                    color: AppConfig.success,
                  ),
                ),
              ],
            ),
          ),
          if (sequenceTitle != null || onSkip != null)
            _TutorialSequenceRow(title: sequenceTitle, onSkip: onSkip),
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

/// The line under the progress bar: which walkthrough this is, and the way
/// out of it. The skip is a real labelled button because the overlay hides
/// everything under it from assistive tech, so every control it adds must
/// stand on its own.
class _TutorialSequenceRow extends StatelessWidget {
  final String? title;
  final VoidCallback? onSkip;

  const _TutorialSequenceRow({required this.title, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        children: [
          if (title != null)
            Expanded(
              child: Text(
                title!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          if (onSkip != null)
            TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                textStyle: theme.textTheme.labelSmall,
              ),
              child: Text(L10n.of(context).skip),
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
