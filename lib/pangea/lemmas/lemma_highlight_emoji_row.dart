import 'package:flutter/material.dart';

import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_updater_mixin.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_meaning_builder.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LemmaHighlightEmojiRow extends StatefulWidget {
  final ConstructIdentifier cId;
  final String langCode;
  final String targetId;

  final Function(String, String) onEmojiSelected;
  final Map<String, dynamic> messageInfo;

  final String? emoji;
  final Widget? selectedEmojiBadge;
  final bool enabled;

  const LemmaHighlightEmojiRow({
    super.key,
    required this.cId,
    required this.langCode,
    required this.targetId,
    required this.onEmojiSelected,
    required this.messageInfo,
    this.emoji,
    this.selectedEmojiBadge,
    this.enabled = true,
  });

  @override
  State<LemmaHighlightEmojiRow> createState() => LemmaHighlightEmojiRowState();
}

class LemmaHighlightEmojiRowState extends State<LemmaHighlightEmojiRow>
    with AnalyticsUpdater {
  @override
  Widget build(BuildContext context) {
    return LemmaMeaningBuilder(
      langCode: widget.langCode,
      constructId: widget.cId,
      messageInfo: widget.messageInfo,
      builder: (context, controller) {
        return switch (controller.state) {
          AsyncError() => const SizedBox.shrink(),
          AsyncLoaded(value: final lemmaInfo) => SizedBox(
            height: 70.0,
            child: Row(
              spacing: 4.0,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...lemmaInfo.emoji.map((emoji) {
                  final targetId = "${widget.targetId}-$emoji";
                  return EmojiChoiceItem(
                    cId: widget.cId,
                    emoji: emoji,
                    onSelectEmoji: () =>
                        widget.onEmojiSelected(emoji, targetId),
                    selected: widget.emoji == emoji,
                    transformTargetId: targetId,
                    badge: widget.emoji == emoji
                        ? widget.selectedEmojiBadge
                        : null,
                    showShimmer: widget.emoji == null,
                    enabled: widget.enabled,
                  );
                }),
              ],
            ),
          ),
          _ => SizedBox(
            height: 70.0,
            child: Row(
              spacing: 4.0,
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (_) => Shimmer.fromColors(
                  baseColor: Colors.transparent,
                  highlightColor: Theme.of(
                    context,
                  ).colorScheme.primary.withAlpha(70),
                  child: Container(
                    height: 55.0,
                    width: 55.0,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(
                        AppConfig.borderRadius,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        };
      },
    );
  }
}

class EmojiChoiceItem extends StatefulWidget {
  final ConstructIdentifier cId;
  final String emoji;
  final VoidCallback onSelectEmoji;
  final bool selected;
  final String transformTargetId;
  final Widget? badge;
  final bool showShimmer;
  final bool enabled;

  const EmojiChoiceItem({
    super.key,
    required this.cId,
    required this.emoji,
    required this.selected,
    required this.onSelectEmoji,
    required this.transformTargetId,
    this.badge,
    this.showShimmer = true,
    this.enabled = true,
  });

  @override
  State<EmojiChoiceItem> createState() => EmojiChoiceItemState();
}

class EmojiChoiceItemState extends State<EmojiChoiceItem> {
  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (context, hovered) => MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onSelectEmoji : null,
          child: Stack(
            children: [
              ShimmerBackground(
                enabled: widget.showShimmer && widget.enabled,
                delayBetweenPulses: const Duration(seconds: 5),
                child: CompositedTransformTarget(
                  link: MatrixState.pAnyState
                      .layerLinkAndKey(widget.transformTargetId)
                      .link,
                  child: AnimatedContainer(
                    key: MatrixState.pAnyState
                        .layerLinkAndKey(widget.transformTargetId)
                        .key,
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.enabled && (hovered || widget.selected)
                          ? Theme.of(
                              context,
                            ).colorScheme.secondary.withAlpha(30)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        AppConfig.borderRadius,
                      ),
                      border: widget.selected
                          ? Border.all(color: Colors.transparent, width: 4)
                          : null,
                    ),
                    child: Text(
                      widget.emoji,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),
              ),
              if (widget.badge != null)
                Positioned(right: 6, bottom: 6, child: widget.badge!),
            ],
          ),
        ),
      ),
    );
  }
}
