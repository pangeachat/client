import 'dart:math';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';

const double tokenButtonHeight = 40.0;
const double tokenButtonDefaultFontSize = 10;
const int maxEmojisPerLemma = 3;
const double estimatedEmojiWidthRatio = 2;
const double estimatedEmojiHeightRatio = 1.3;

class MessageTokenButton extends StatefulWidget {
  final MessageOverlayController? overlayController;
  final PangeaToken token;
  final TextStyle textStyle;
  final double width;
  final bool animate;

  const MessageTokenButton({
    super.key,
    required this.overlayController,
    required this.token,
    required this.textStyle,
    required this.width,
    this.animate = false,
  });

  @override
  MessageTokenButtonState createState() => MessageTokenButtonState();
}

class MessageTokenButtonState extends State<MessageTokenButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: AppConfig.overlayAnimationDuration,
        // seconds: 5,
      ),
    );

    _heightAnimation = Tween<double>(
      begin: 0,
      end: tokenButtonHeight,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    if (widget.animate) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant MessageTokenButton oldWidget) {
    if (oldWidget.overlayController?.toolbarMode !=
        widget.overlayController?.toolbarMode) {
      setState(() {});
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get tokenTextWidth => widget.width;

  double get textSize =>
      widget.textStyle.fontSize ?? tokenButtonDefaultFontSize;

  double get emojiSize => textSize * estimatedEmojiWidthRatio;

  double get totalAvailableWidth => tokenTextWidth;

  TextStyle get emojiStyle => widget.textStyle.copyWith(
        fontSize: textSize - 2,
      );

  Widget get content {
    switch (widget.overlayController!.toolbarMode) {
      case MessageMode.wordEmoji:
        if (widget.token.text.content.length == 1) {
          return Text(
            widget.token.vocabConstructID.userSetEmoji.firstOrNull ?? '',
            style: emojiStyle,
          );
        }
        return Stack(
          alignment: Alignment.center,
          children: widget.token.vocabConstructID.userSetEmoji
              .take(maxEmojisPerLemma)
              .mapIndexed(
                (index, emoji) => Positioned(
                  left: min(
                    index /
                        widget.token.vocabConstructID.userSetEmoji.length *
                        totalAvailableWidth,
                    index * emojiSize,
                  ),
                  child: Text(
                    emoji,
                    style: emojiStyle,
                  ),
                ),
              )
              .toList()
              .reversed
              .toList(),
        );
      default:
        return const SizedBox(height: tokenButtonHeight);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return widget.overlayController != null
          ? Container(
              height: tokenButtonHeight,
              padding: const EdgeInsets.only(top: 10.0),
              width: widget.width,
              alignment: Alignment.center,
              child: content,
            )
          : const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _heightAnimation,
      builder: (context, child) {
        return widget.overlayController != null
            ? Container(
                height: _heightAnimation.value,
                padding: const EdgeInsets.only(top: 10.0),
                width: widget.width,
                alignment: Alignment.center,
                child: content,
              )
            : const SizedBox.shrink();
      },
    );
  }
}
