import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/subscription/widgets/decorative_stars.dart';
import 'package:fluffychat/features/subscription/widgets/locked_shimmer_box.dart';
import 'package:fluffychat/features/subscription/widgets/unlock_button.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The subscription gate that stands where a finished activity's summary would
/// have landed (#8860).
///
/// Built from the same kit as every other gate — [LockedShimmerBox] skeleton,
/// [DecorativeStars] texture, [UnlockButton] call to action (#7929) — and
/// wearing the summary's own box: the same padding, margin, width cap and
/// half-alpha surface [ActivityUserSummaries] uses, so the gate lands exactly
/// where the thing it replaces would.
///
/// The skeleton traces that summary's real shape — its heading, the feedback
/// itself, the participant picker, and the goal list beneath it — because a
/// gate that shows what is missing sells the feature, where the bare line this
/// replaced only reported that something was locked.
class ActivitySummaryUnsubscribedCard extends StatelessWidget {
  /// The gold block standing in for the summary text itself. Medium and
  /// tinted, so the eye lands on the thing being withheld rather than reading
  /// the skeleton as a row of empty lines.
  static const double _summaryHeight = 76.0;

  static const double _avatarSize = 40.0;

  /// How many picker circles to draw — one per learner in a role, so the row
  /// matches the activity it belongs to. Zero draws no row at all: a wrong
  /// count is worse than none, since the picker is the one part of the
  /// skeleton whose shape carries information.
  final int roleCount;

  const ActivitySummaryUnsubscribedCard({required this.roleCount, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The button must be its OWN semantics node. Flutter web paints the
    // semantics tree as real DOM elements over the canvas, and a click on one
    // fires that node's tap action as a synthetic tap at the node's CENTRE. In
    // the timeline the gate's only action — the button's — was being absorbed
    // into the node for the whole list row, so a click anywhere in that row,
    // even beside the card, was re-aimed at the row's centre, landed on the
    // pill, and opened the subscription page (#8860). `explicitChildNodes`
    // stops the absorption: the button keeps a node of its own, sized to
    // itself, and the row-sized node it used to hide in carries no action.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      // The timeline wraps every row in a SelectionArea
      // (chat_event_list.dart), which makes this card's text selectable and
      // hands its label the I-beam cursor no other button wears. Opting the
      // whole gate out is what [Message] already does for its own chrome
      // (message.dart).
      child: SelectionContainer.disabled(
        child: Center(
          // The gate is a SURFACE with exactly one control. Every tap that is
          // not on the button stops here: the skeleton below is wrapped in an
          // IgnorePointer so it can never take one, and this opaque hit keeps
          // what lands in the gaps from reaching the timeline underneath.
          // Children are hit-tested first, so the button keeps its own taps.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              margin: const EdgeInsets.all(16.0),
              // The summary's own width cap, shared with the goal header and the
              // plan page.
              constraints: const BoxConstraints(
                maxWidth: FluffyThemes.columnWidth * 1.5,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withAlpha(128),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // A skeleton of the real summary, in its order: the finished
                  // heading, the feedback body, the participant picker, then the
                  // goals under it. Pointer-blind: it is a picture of content,
                  // and nothing in it is meant to be clickable.
                  IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LockedShimmerBox(width: 200, height: 18),
                        const SizedBox(height: 14.0),
                        LockedShimmerBox(
                          // Tinted like the practice page's example message, so the
                          // summary reads as the content and not as more chrome.
                          baseColor: AppConfig.goldByTheme(
                            context,
                          ).withAlpha(70),
                          width: double.infinity,
                          height: _summaryHeight,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        if (roleCount > 0) ...[
                          const SizedBox(height: 22.0),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: 12.0,
                            children: [
                              for (int i = 0; i < roleCount; i++)
                                LockedShimmerBox(
                                  width: _avatarSize,
                                  height: _avatarSize,
                                  borderRadius: BorderRadius.circular(
                                    _avatarSize / 2,
                                  ),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 20.0),
                        const LockedShimmerBox(
                          width: double.infinity,
                          height: 14,
                        ),
                        const SizedBox(height: 8.0),
                        const LockedShimmerBox(width: 220, height: 14),
                      ],
                    ),
                  ),
                  // Texture, listed before the call to action so it never eats the
                  // label's contrast. Unequal sizes and insets — a matched pair at
                  // opposite corners reads as a frame rather than a scatter
                  // (#7929).
                  const DecorativeStars(
                    stars: [
                      DecorativeStarSpec(
                        size: 72.0,
                        top: -8.0,
                        left: 14.0,
                        rotation: -0.22,
                      ),
                      DecorativeStarSpec(
                        size: 30.0,
                        top: 104.0,
                        right: -6.0,
                        rotation: -0.6,
                      ),
                      DecorativeStarSpec(
                        size: 46.0,
                        bottom: 2.0,
                        right: 28.0,
                        rotation: 0.45,
                      ),
                    ],
                  ),
                  // The label has to FIT ON ONE LINE, which is the whole
                  // reason the kit's labels name the feature alone ("Unlock word
                  // tools") instead of pitching the purchase. A wrapped [Text]
                  // fills its constraints, so the longer
                  // "Subscribe to unlock activity summaries" — 657px of natural
                  // width against the card's 538 — turned this pill into a
                  // full-width band 74px tall, and clicks from most of the card
                  // landed on it (#8860). Shorter label, and the pill hugs it.
                  UnlockButton(
                    label: L10n.of(context).unlockActivitySummaries,
                    fontSize: 16.0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 12.0,
                    ),
                    showStars: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
