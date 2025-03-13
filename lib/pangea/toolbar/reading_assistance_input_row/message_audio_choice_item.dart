import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/toolbar/controllers/tts_controller.dart';

class MessageAudioChoiceItem extends StatefulWidget {
  const MessageAudioChoiceItem({
    super.key,
    required this.wordForm,
    required this.onTap,
    required this.isSelected,
    required this.isGold,
    required this.ttsController,
  });

  final String wordForm;
  final void Function() onTap;
  final bool isSelected;
  final bool? isGold;
  final TtsController ttsController;

  @override
  MessageAudioChoiceItemState createState() => MessageAudioChoiceItemState();
}

class MessageAudioChoiceItemState extends State<MessageAudioChoiceItem> {
  bool _isHovered = false;
  bool _isPlaying = false;

  @override
  void didUpdateWidget(covariant MessageAudioChoiceItem oldWidget) {
    if (oldWidget.isSelected != widget.isSelected ||
        oldWidget.isGold != widget.isGold) {
      setState(() {});
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<void> onTap() async {
    widget.onTap();

    if (_isPlaying) {
      await widget.ttsController.stop();
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    } else {
      if (mounted) {
        setState(() => _isPlaying = true);
      }
      try {
        await widget.ttsController.tryToSpeak(
          widget.wordForm,
          context,
          targetID: 'word-audio-button',
        );
      } catch (e, s) {
        debugger(when: kDebugMode);
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {"text": widget.wordForm},
        );
      } finally {
        if (mounted) {
          setState(() => _isPlaying = false);
        }
      }
    }
  }

  Color get _color {
    if (widget.isSelected && widget.isGold != null) {
      return widget.isGold!
          ? AppConfig.success.withAlpha((0.2 * 255).toInt())
          : AppConfig.warning.withAlpha((0.2 * 255).toInt());
    }
    if (widget.isSelected) {
      return AppConfig.primaryColor.withAlpha((0.3 * 255).toInt());
    }
    return _isHovered
        ? AppConfig.primaryColor.withAlpha((0.1 * 255).toInt())
        : Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            color: _color,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Container(
            padding: const EdgeInsets.all(8.0),
            child:
                Icon(_isPlaying ? Icons.play_arrow : Icons.play_arrow_outlined),
          ),
        ),
      ),
    );
  }
}
