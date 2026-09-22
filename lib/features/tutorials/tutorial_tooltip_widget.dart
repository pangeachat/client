import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/features/tutorials/tutorial_copy.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_word_bubble.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';

class TutorialTooltipWidget extends StatefulWidget {
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

  /// What activating the message does — the keyboard's and the screen
  /// reader's tap-anywhere: advancing a tap step, dismissing an armed one. The
  /// message is then one named button whose name is the step's copy. Null on a
  /// branch step, whose choices are the answers; the message is a named group
  /// there. See tutorials.instructions.md § Accessibility.
  final VoidCallback? onActivate;

  /// Spoken after the message as what activating it does ("Continue",
  /// "Dismiss"). Ignored without [onActivate].
  final String? activateHint;

  const TutorialTooltipWidget({
    required this.text,
    required this.currentStep,
    required this.totalSteps,
    this.sequenceTitle,
    this.onSkip,
    this.choices = const [],
    this.onChoice,
    this.wordBubble,
    this.onActivate,
    this.activateHint,
    super.key,
  });

  /// The bot face is the card's speaker; at the old 32px it read as an icon
  /// rather than a sender avatar.
  static const double _botFaceSize = 44.0;

  @override
  State<TutorialTooltipWidget> createState() => _TutorialTooltipWidgetState();
}

class _TutorialTooltipWidgetState extends State<TutorialTooltipWidget> {
  /// The message's focus node. It outlives every step — the card is one
  /// element for the whole run — so focus lands here once, when the run
  /// opens, and never has to be moved again: a live region announces each
  /// new step in place.
  final FocusNode _focusNode = FocusNode(debugLabel: 'tutorial message');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
    // Post-frame, not autofocus: the overlay's own scope takes focus in the
    // same frame (OverlayKeyboardModal), and autofocus yields to that.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode _) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final style = theme.textTheme.bodyMedium;

    final progress = widget.totalSteps > 0
        ? widget.currentStep / widget.totalSteps
        : 0.0;

    final onActivate = widget.onActivate;
    final wordBubble = widget.wordBubble;
    final choices = widget.choices;

    // One node — name, role, focus, action — so a screen reader hears the
    // message and can act on it in place, and the keyboard's Enter or Space
    // does the same. Actions rather than a shortcuts wrapper: a key event
    // bubbles up from the focused node, so a wrapper here would answer Enter
    // before the Skip button could; an intent resolves from the focused node
    // outward, so the button wins while it has focus. A live region, so a new
    // step's copy is read without moving focus. The row inside is excluded
    // (the face is decoration, the text IS the label).
    final message = Semantics(
      key: const ValueKey('tutorial-message'),
      container: true,
      liveRegion: true,
      button: onActivate != null,
      label: widget.text,
      hint: onActivate == null ? null : widget.activateHint,
      onTap: onActivate,
      child: Actions(
        actions: <Type, Action<Intent>>{
          if (onActivate != null) ...{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                onActivate();
                return null;
              },
            ),
            ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
              onInvoke: (_) {
                onActivate();
                return null;
              },
            ),
          },
        },
        child: Focus(
          focusNode: _focusNode,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: ExcludeSemantics(
            child: Row(
              spacing: 8.0,
              // Top-aligned like a chat message: the avatar sits at the head
              // of the text, not floating beside its middle.
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BotFace(
                  width: TutorialTooltipWidget._botFaceSize,
                  expression: BotExpression.gold,
                ),
                Expanded(
                  child: Text(
                    widget.text,
                    style: style,
                    textAlign: TextAlign.start,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final card = Container(
      // Tighter on top than elsewhere: the message block centers itself in the
      // card's slack, so top padding stacks onto that slack. Sides and bottom
      // match, so the bottom row (buttons, skip/title) sits at the same
      // distance from every edge it touches.
      padding: const EdgeInsets.fromLTRB(14.0, 4.0, 14.0, 14.0),
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
                          _TutorialGreeting(greeting: wordBubble),
                          const SizedBox(height: 8.0),
                        ],
                        message,
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
                  "${widget.currentStep} / ${widget.totalSteps}",
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  // Silent: the text beside it says what the bar shows, and a
                  // progress role merging into the card would misname it.
                  child: ExcludeSemantics(
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8.0,
                      borderRadius: BorderRadius.circular(
                        AppConfig.borderRadius,
                      ),
                      // Green from the first step: the bar reports progress
                      // made, and a color that only arrives at the end read as
                      // the earlier steps not counting. The mark tone, so the
                      // fill clears 3:1 on the card in both themes.
                      color: theme.pangea.successGraphic,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Under the progress bar, the card's bottom line. A branch step
          // carries no title row — it is already a question with two answers,
          // and a label wedged against them read as part of neither.
          if (choices.isEmpty &&
              (widget.sequenceTitle != null || widget.onSkip != null))
            _TutorialSequenceRow(
              title: widget.sequenceTitle,
              onSkip: widget.onSkip,
            ),
          if (choices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                spacing: 8.0,
                children: [
                  // The declining choice always sits LEFT of the advancing one
                  // — the same corner the Skip control lives in, so the way
                  // out of a walkthrough is in one place everywhere.
                  for (final choice in [
                    ...choices.where(
                      (c) => c.outcome == TutorialChoiceOutcome.decline,
                    ),
                    ...choices.where(
                      (c) => c.outcome != TutorialChoiceOutcome.decline,
                    ),
                  ])
                    Expanded(
                      child: _TutorialChoiceButton(
                        label: choice.label,
                        // The app's colour hierarchy: the filled primary leads
                        // (the advancing choice); the decline is a fully filled
                        // tonal secondaryContainer button, as in the CTA row.
                        secondary:
                            choice.outcome != TutorialChoiceOutcome.advance,
                        onPressed: () => widget.onChoice?.call(choice.outcome),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    // The ring frames the whole card, because the whole card is what a tap
    // lands on, even though the focus sits on the message.
    return FocusRing(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppConfig.borderRadius)),
      ),
      show: _focused && FocusRingTapTarget.highlightsEnabled,
      child: card,
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
    // The way out sits bottom-LEFT and the walkthrough's name bottom-right —
    // the same corners the branch step's choices take.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        children: [
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
          Expanded(
            child: title == null
                ? const SizedBox.shrink()
                : Text(
                    title!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
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
        backgroundColor: secondary ? scheme.secondaryContainer : scheme.primary,
        foregroundColor: secondary
            ? scheme.onSecondaryContainer
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
