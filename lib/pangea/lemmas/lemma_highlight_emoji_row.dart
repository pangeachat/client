import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_misc/get_analytics_controller.dart';
import 'package:fluffychat/pangea/analytics_misc/lemma_emoji_setter_mixin.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_meaning_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LemmaHighlightEmojiRow extends StatefulWidget {
  final LemmaMeaningBuilderState controller;
  final ConstructIdentifier cId;

  const LemmaHighlightEmojiRow({
    super.key,
    required this.controller,
    required this.cId,
  });

  @override
  LemmaHighlightEmojiRowState createState() => LemmaHighlightEmojiRowState();
}

class LemmaHighlightEmojiRowState extends State<LemmaHighlightEmojiRow>
    with LemmaEmojiSetter {
  bool _showShimmer = true;
  String? _selectedEmoji;

  late StreamSubscription<AnalyticsStreamUpdate> _analyticsSubscription;
  Timer? _shimmerTimer;

  @override
  void initState() {
    super.initState();
    _analyticsSubscription = MatrixState
        .pangeaController.getAnalytics.analyticsStream.stream
        .listen(_onAnalyticsUpdate);
    _setShimmer();
  }

  @override
  void didUpdateWidget(LemmaHighlightEmojiRow oldWidget) {
    if (oldWidget.cId != widget.cId) _setShimmer();
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _analyticsSubscription.cancel();
    _shimmerTimer?.cancel();
    super.dispose();
  }

  void _setShimmer() {
    setState(() {
      _selectedEmoji = widget.cId.userSetEmoji.firstOrNull;
      _showShimmer = _selectedEmoji == null;

      if (_showShimmer) {
        _shimmerTimer?.cancel();
        _shimmerTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) {
            setState(() {
              _showShimmer = false;
              _shimmerTimer?.cancel();
              _shimmerTimer = null;
            });
          }
        });
      }
    });
  }

  void _onAnalyticsUpdate(AnalyticsStreamUpdate update) {
    if (update.targetID != null) {
      OverlayUtil.showPointsGained(update.targetID!, update.points, context);
    }
  }

  Future<void> _setEmoji(String emoji, BuildContext context) async {
    try {
      setState(() => _selectedEmoji = emoji);
      await setLemmaEmoji(
        widget.cId,
        emoji,
        "emoji-choice-item-$emoji-${widget.cId.lemma}",
      );
      showLemmaEmojiSnackbar(context, widget.cId, emoji);
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
                    onSelectEmoji: () => _setEmoji(emoji, context),
                    isDisplay: _selectedEmoji == emoji,
                    showShimmer: _showShimmer,
                    transformTargetId:
                        "emoji-choice-item-$emoji-${widget.cId.lemma}",
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
  final String transformTargetId;

  const EmojiChoiceItem({
    super.key,
    required this.emoji,
    required this.isDisplay,
    required this.onSelectEmoji,
    required this.showShimmer,
    required this.transformTargetId,
  });

  @override
  EmojiChoiceItemState createState() => EmojiChoiceItemState();
}

class EmojiChoiceItemState extends State<EmojiChoiceItem> {
  bool _isHovered = false;

  LayerLink get layerLink =>
      MatrixState.pAnyState.layerLinkAndKey(widget.transformTargetId).link;

  @override
  Widget build(BuildContext context) {
    final shimmerColor = (Theme.of(context).brightness == Brightness.dark)
        ? Colors.white
        : Theme.of(context).colorScheme.primary;
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
                      baseColor: shimmerColor.withValues(alpha: 0.1),
                      highlightColor: shimmerColor.withValues(alpha: 0.6),
                      direction: ShimmerDirection.ltr,
                      child: Container(
                        decoration: BoxDecoration(
                          color: shimmerColor.withValues(alpha: 0.3),
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
