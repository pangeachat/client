import 'dart:developer';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/toolbar/controllers/tts_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class MessageChoiceItem extends StatefulWidget {
  const MessageChoiceItem({
    super.key,
    required this.content,
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    required this.isSelected,
    this.contentOpacity = 1.0,
    required this.isGold,
    this.buttonSize,
    this.audioContent,
    this.ttsController,
  });

  final Widget content;
  final void Function() onTap;
  final void Function()? onDoubleTap;
  final void Function()? onLongPress;
  final bool isSelected;
  final double contentOpacity;
  final bool? isGold;
  final Size? buttonSize;
  final String? audioContent;
  final TtsController? ttsController;

  @override
  MessageChoiceItemState createState() => MessageChoiceItemState();
}

class MessageChoiceItemState extends State<MessageChoiceItem> {
  bool _isHovered = false;
  bool _isPlaying = false;

  Future<void> play() async {
    if (widget.audioContent == null || widget.ttsController == null) {
      return;
    }

    if (_isPlaying) {
      await widget.ttsController!.stop();
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    } else {
      if (mounted) {
        setState(() => _isPlaying = true);
      }
      try {
        await widget.ttsController!.tryToSpeak(
          widget.audioContent!,
          context,
          targetID: 'word-audio-button',
        );
      } catch (e, s) {
        debugger(when: kDebugMode);
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {"text": widget.audioContent},
        );
      } finally {
        if (mounted) {
          setState(() => _isPlaying = false);
        }
      }
    }
  }

  @override
  didUpdateWidget(MessageChoiceItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSelected != widget.isSelected ||
        oldWidget.isGold != widget.isGold) {
      setState(() {});
    }
  }

  Color get color {
    if (widget.isSelected) {
      debugPrint('widget.isGold: ${widget.isGold}');
      if (widget.isGold == null) {
        return AppConfig.primaryColor.withAlpha((0.4 * 255).toInt());
      } else {
        return widget.isGold!
            ? AppConfig.success.withAlpha((0.4 * 255).toInt())
            : AppConfig.warning.withAlpha((0.4 * 255).toInt());
      }
    }
    if (_isHovered) {
      return AppConfig.primaryColor.withAlpha((0.2 * 255).toInt());
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.contentOpacity,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          onTap: () {
            play();
            widget.onTap();
          },
          onLongPress: widget.onLongPress,
          child: IntrinsicWidth(
            child: Container(
              height: widget.buttonSize?.height,
              width: widget.buttonSize?.width,
              alignment: Alignment.center,
              padding: widget.buttonSize == null
                  ? const EdgeInsets.all(8)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              ),
              child: widget.content,
            ),
          ),
        ),
      ),
    );
  }
}
