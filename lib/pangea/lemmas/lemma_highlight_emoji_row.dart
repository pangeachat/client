import 'dart:developer';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_misc/gain_points_animation.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/toolbar/widgets/word_zoom/lemma_meaning_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class LemmmaHighlightEmojiRow extends StatefulWidget {
  final LemmaMeaningBuilderState controller;
  final ConstructIdentifier cId;
  final VoidCallback? onTapOverride;
  final bool isSelected;
  final double? iconSize;

  const LemmmaHighlightEmojiRow({
    super.key,
    required this.controller,
    required this.cId,
    required this.onTapOverride,
    required this.isSelected,
    this.iconSize,
  });

  @override
  LemmmaHighlightEmojiRowState createState() => LemmmaHighlightEmojiRowState();
}

class LemmmaHighlightEmojiRowState extends State<LemmmaHighlightEmojiRow> {
  String? displayEmoji;
  bool _showShimmer = true;
  bool _hasShimmered = false;

  @override
  void initState() {
    super.initState();
    displayEmoji = widget.cId.userSetEmoji.firstOrNull;
    _showShimmer = (displayEmoji == null);
  }

  void _startShimmer() {
    if (!widget.controller.isLoading && _showShimmer) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() => _showShimmer = false);
          setState(() => _hasShimmered = true);
        }
      });
    }
  }

  @override
  didUpdateWidget(LemmmaHighlightEmojiRow oldWidget) {
    // Check if the construct identifier changed (new word/construct)
    if (oldWidget.cId != widget.cId) {
      // Reset shimmer state for new construct
      setState(() {
        displayEmoji = widget.cId.userSetEmoji.firstOrNull;
        _showShimmer = (displayEmoji == null);
        _hasShimmered = false;
      });
    } else if (oldWidget.isSelected != widget.isSelected ||
        widget.cId.userSetEmoji != oldWidget.cId.userSetEmoji) {
      setState(() => displayEmoji = widget.cId.userSetEmoji.firstOrNull);
    }

    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> setEmoji(String emoji, BuildContext context) async {
    if(widget.cId.userSetEmoji.firstOrNull == null){
      debugPrint("SetState called for FIRST emoji");
      final String targetID = "emoji-choice-item-$emoji-${widget.cId.lemma}";
      OverlayUtil.showOverlay(
        overlayKey: "${targetID}_points",
        followerAnchor: Alignment.bottomCenter,
        targetAnchor: Alignment.bottomCenter,
        context: context,
        child: PointsGainedAnimation(
          points: 2,
          targetID: "emoji-choice-item-$emoji-${widget.cId.lemma}",
        ),
        transformTargetId: targetID,
        closePrevOverlay: false,
        backDropToDismiss: false,
        ignorePointer: true,
      );
    }
    try {
      setState(() => displayEmoji = emoji);
      // Use new method that awards XP for first-time emoji selections
      await widget.cId.setEmojiWithXP(
        emoji: emoji,
        isFromCorrectAnswer: false,
      );
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(data: widget.cId.toJson(), e: e, s: s);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.isLoading) {
      return const CircularProgressIndicator.adaptive();
    }
    _startShimmer();

    final emojis = widget.controller.lemmaInfo?.emoji;
    if (widget.controller.error != null || emojis == null || emojis.isEmpty) {
      return const SizedBox.shrink();
    }

    return Material(
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      child: Container(
        padding: const EdgeInsets.all(8),
        height: 80,
        alignment: Alignment.center,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: emojis
                .map(
                  (emoji) => EmojiChoiceItem(
                    emoji: emoji,
                    cId: widget.cId,
                    onSelectEmoji: () => setEmoji(emoji, context),
                    // will highlight selected emoji
                    isDisplay: (displayEmoji == emoji),
                    showShimmer: (_showShimmer && !_hasShimmered),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class EmojiChoiceItem extends StatefulWidget {
  final String emoji;
  final VoidCallback onSelectEmoji;
  final bool isDisplay;
  final bool showShimmer;
  final ConstructIdentifier cId;



  const EmojiChoiceItem({
    super.key,
    required this.emoji,
    required this.isDisplay,
    required this.onSelectEmoji,
    required this.showShimmer,
    required this.cId,
  });

  @override
  EmojiChoiceItemState createState() => EmojiChoiceItemState();
}

class EmojiChoiceItemState extends State<EmojiChoiceItem> {
  bool _isHovered = false;

//Get transform targetID so points can come off of selected emoji
  String get transformTargetId => "emoji-choice-item-${widget.emoji}-${widget.cId.lemma}";

  LayerLink get layerLink =>
      MatrixState.pAnyState.layerLinkAndKey(transformTargetId).link;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onSelectEmoji,
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Stack(
            children: [
              CompositedTransformTarget(
              link: layerLink,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isHovered
                        ? Theme.of(context).colorScheme.primary.withAlpha(50)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                    border: widget.isDisplay
                        ? Border.all(
                            color: AppConfig.goldLight,
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
              if (widget.showShimmer)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                    child: Shimmer.fromColors(
                      baseColor: Colors.white.withValues(alpha: 0.1),
                      highlightColor: Colors.white.withValues(alpha: 0.6),
                      direction: ShimmerDirection.ltr,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius:
                              BorderRadius.circular(AppConfig.borderRadius),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
