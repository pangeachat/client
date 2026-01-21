import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/chat/events/audio_player.dart';
import 'package:fluffychat/pangea/analytics_misc/text_loading_shimmer.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/text_to_speech/text_to_speech_response_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class MessageAudioCard extends StatefulWidget {
  final PangeaMessageEvent messageEvent;
  final VoidCallback? onError;

  const MessageAudioCard({
    super.key,
    required this.messageEvent,
    this.onError,
  });

  @override
  MessageAudioCardState createState() => MessageAudioCardState();
}

class MessageAudioCardState extends State<MessageAudioCard> {
  bool _isLoading = false;
  PangeaAudioFile? audioFile;

  @override
  void initState() {
    super.initState();
    fetchAudio();
  }

  Future<void> fetchAudio() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      audioFile = await widget.messageEvent.requestTextToSpeech(
        widget.messageEvent.messageDisplayLangCode,
        MatrixState.pangeaController.userController.voice,
      );
      debugPrint("audio file is now: $audioFile. setting starts and ends...");
      if (mounted) setState(() => _isLoading = false);
    } catch (e, s) {
      widget.onError?.call();
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        e: e,
        s: s,
        m: 'something wrong getting audio in MessageAudioCardState',
        data: {
          'widget.messageEvent.messageDisplayLangCode':
              widget.messageEvent.messageDisplayLangCode,
        },
      );
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60.0,
      alignment: Alignment.center,
      child: _isLoading
          ? const TextLoadingShimmer(width: 200)
          : audioFile != null
              ? AudioPlayerWidget(
                  null,
                  eventId: "${widget.messageEvent.eventId}_practice",
                  roomId: widget.messageEvent.room.id,
                  senderId: widget.messageEvent.senderId,
                  matrixFile: audioFile,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontSize:
                      AppConfig.messageFontSize * AppConfig.fontSizeFactor,
                  linkColor: Theme.of(context).brightness == Brightness.light
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onPrimary,
                )
              : const SizedBox(),
    );
  }
}

class PangeaAudioFile extends MatrixAudioFile {
  List<int>? waveform;
  List<TTSToken>? tokens;

  PangeaAudioFile({
    required super.bytes,
    required super.name,
    super.mimeType,
    super.duration,
    this.waveform,
    required this.tokens,
  });
}
