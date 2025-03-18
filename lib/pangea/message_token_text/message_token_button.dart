import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:flutter/material.dart';

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

  const MessageTokenButton({
    super.key,
    required this.overlayController,
    required this.token,
    required this.textStyle,
    required this.width,
  });

  @override
  MessageTokenButtonState createState() => MessageTokenButtonState();
}

class MessageTokenButtonState extends State<MessageTokenButton> {
  /// remove tapped emoji from the lemma
  // Future<void> onTap() async {
  //   widget.overlayController.onTokenButtonTap(widget.token);
  // }

  // double get tokenTextWidth =>
  //     widget.token.text.length *
  //     (widget.textStyle.fontSize ?? tokenButtonDefaultFontSize);

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
  void didUpdateWidget(covariant MessageTokenButton oldWidget) {
    if (oldWidget.overlayController?.toolbarMode !=
        widget.overlayController?.toolbarMode) {
      setState(() {});
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration:
          const Duration(milliseconds: AppConfig.overlayAnimationDuration),
      height: widget.overlayController != null
          ? textSize * estimatedEmojiHeightRatio + 10
          : 0.0,
      child: widget.overlayController != null
          ? Container(
              height: textSize * estimatedEmojiHeightRatio,
              padding: const EdgeInsets.only(top: 10.0),
              width: widget.width,
              alignment: Alignment.center,
              child: content,
            )
          : const SizedBox.shrink(),
    );
  }
}
