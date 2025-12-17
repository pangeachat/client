import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_misc/get_analytics_controller.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_meaning_builder.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LemmaHighlightEmojiRow extends StatefulWidget {
  final ConstructIdentifier cId;
  final String langCode;

  final Function(String) onEmojiSelected;

  final String? emoji;
  final Widget? selectedEmojiBadge;

  const LemmaHighlightEmojiRow({
    super.key,
    required this.cId,
    required this.langCode,
    required this.onEmojiSelected,
    this.emoji,
    this.selectedEmojiBadge,
  });

  @override
  State<LemmaHighlightEmojiRow> createState() => LemmaHighlightEmojiRowState();
}

class LemmaHighlightEmojiRowState extends State<LemmaHighlightEmojiRow> {
  late StreamSubscription<AnalyticsStreamUpdate> _analyticsSubscription;

  @override
  void initState() {
    super.initState();
    _analyticsSubscription = MatrixState
        .pangeaController.getAnalytics.analyticsStream.stream
        .listen(_onAnalyticsUpdate);
  }

  @override
  void dispose() {
    _analyticsSubscription.cancel();
    super.dispose();
  }

  void _onAnalyticsUpdate(AnalyticsStreamUpdate update) {
    if (update.targetID != null) {
      OverlayUtil.showPointsGained(update.targetID!, update.points, context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LemmaMeaningBuilder(
      langCode: widget.langCode,
      constructId: widget.cId,
      builder: (context, controller) {
        if (controller.isLoading) {
          return const CircularProgressIndicator.adaptive();
        }

        final emojis = controller.lemmaInfo?.emoji;
        if (controller.error != null || emojis == null || emojis.isEmpty) {
          return const SizedBox.shrink();
        }

        return SizedBox(
          height: 70.0,
          child: Row(
            spacing: 4.0,
            mainAxisSize: MainAxisSize.min,
            children: emojis
                .map(
                  (emoji) => EmojiChoiceItem(
                    cId: widget.cId,
                    emoji: emoji,
                    onSelectEmoji: () => widget.onEmojiSelected(emoji),
                    selected: widget.emoji == emoji,
                    transformTargetId:
                        "emoji-choice-item-$emoji-${widget.cId.lemma}",
                    badge: widget.emoji == emoji
                        ? widget.selectedEmojiBadge
                        : null,
                    showShimmer: widget.emoji == null,
                  ),
                )
                .toList(),
          ),
        );
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

  const EmojiChoiceItem({
    super.key,
    required this.cId,
    required this.emoji,
    required this.selected,
    required this.onSelectEmoji,
    required this.transformTargetId,
    this.badge,
    this.showShimmer = true,
  });

  @override
  State<EmojiChoiceItem> createState() => EmojiChoiceItemState();
}

class EmojiChoiceItemState extends State<EmojiChoiceItem> {
  bool shimmer = false;
  Timer? _shimmerTimer;

  @override
  void initState() {
    super.initState();
    _showShimmer();
  }

  @override
  void didUpdateWidget(covariant EmojiChoiceItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emoji != widget.emoji) {
      _showShimmer();
    }
  }

  @override
  void dispose() {
    _shimmerTimer?.cancel();
    super.dispose();
  }

  void _showShimmer() {
    if (!widget.showShimmer) return;

    setState(() => shimmer = true);
    _shimmerTimer?.cancel();
    _shimmerTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => shimmer = false);
    });
  }

  LayerLink get layerLink =>
      MatrixState.pAnyState.layerLinkAndKey(widget.transformTargetId).link;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (context, hovered) => GestureDetector(
        onTap: widget.onSelectEmoji,
        child: Stack(
          children: [
            ShimmerBackground(
              enabled: shimmer,
              shimmerColor: (Theme.of(context).brightness == Brightness.dark)
                  ? Colors.white
                  : Theme.of(context).colorScheme.primary,
              child: CompositedTransformTarget(
                link: layerLink,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: hovered || widget.selected
                        ? Theme.of(context).colorScheme.secondary.withAlpha(30)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                    border: widget.selected
                        ? Border.all(
                            color: Colors.transparent,
                            width: 4,
                          )
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
              Positioned(
                right: 6,
                bottom: 6,
                child: widget.badge!,
              ),
          ],
        ),
      ),
    );
  }
}
