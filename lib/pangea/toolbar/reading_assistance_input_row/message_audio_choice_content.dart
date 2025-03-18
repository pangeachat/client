import 'dart:developer';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/toolbar/controllers/tts_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class MessageAudioChoiceContent extends StatefulWidget {
  const MessageAudioChoiceContent({
    super.key,
    required this.wordForm,
    required this.onTap,
    required this.ttsController,
  });

  final String wordForm;
  final void Function() onTap;
  final TtsController ttsController;

  @override
  MessageAudioChoiceContentState createState() =>
      MessageAudioChoiceContentState();
}

class MessageAudioChoiceContentState extends State<MessageAudioChoiceContent> {
  bool _isPlaying = false;

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

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      onTap: onTap,
      child: Icon(
        Icons.volume_up,
        color: _isPlaying ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }
}
