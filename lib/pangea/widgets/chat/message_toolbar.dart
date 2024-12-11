import 'dart:developer';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/enum/message_mode_enum.dart';
import 'package:fluffychat/pangea/matrix_event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:fluffychat/pangea/widgets/chat/message_audio_card.dart';
import 'package:fluffychat/pangea/widgets/chat/message_selection_overlay.dart';
import 'package:fluffychat/pangea/widgets/chat/message_speech_to_text_card.dart';
import 'package:fluffychat/pangea/widgets/chat/message_translation_card.dart';
import 'package:fluffychat/pangea/widgets/chat/message_unsubscribed_card.dart';
import 'package:fluffychat/pangea/widgets/chat/toolbar_content_loading_indicator.dart';
import 'package:fluffychat/pangea/widgets/chat/tts_controller.dart';
import 'package:fluffychat/pangea/widgets/message_display_card.dart';
import 'package:fluffychat/pangea/widgets/practice_activity/practice_activity_card.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix_api_lite/model/message_types.dart';

const double minCardHeight = 70;

class MessageToolbar extends StatelessWidget {
  final PangeaMessageEvent pangeaMessageEvent;
  final MessageOverlayController overLayController;

  const MessageToolbar({
    super.key,
    required this.pangeaMessageEvent,
    required this.overLayController,
  });

  TtsController get ttsController =>
      overLayController.widget.chatController.choreographer.tts;

  Widget? toolbarContent(BuildContext context) {
    final bool subscribed =
        MatrixState.pangeaController.subscriptionController.isSubscribed;

    if (!subscribed) {
      return MessageUnsubscribedCard(
        controller: overLayController,
      );
    }

    if (!overLayController.initialized) {
      return const ToolbarContentLoadingIndicator();
    }

    switch (overLayController.toolbarMode) {
      case MessageMode.translation:
        return MessageTranslationCard(
          messageEvent: pangeaMessageEvent,
          selection: overLayController.selectedSpan,
        );
      case MessageMode.textToSpeech:
        return MessageAudioCard(
          messageEvent: pangeaMessageEvent,
          overlayController: overLayController,
          selection: overLayController.selectedSpan,
          tts: ttsController,
          setIsPlayingAudio: overLayController.setIsPlayingAudio,
        );
      case MessageMode.speechToText:
        return MessageSpeechToTextCard(
          messageEvent: pangeaMessageEvent,
        );
      case MessageMode.practiceActivity:
        // If not in the target language show specific messsage
        if (!overLayController.messageInUserL2) {
          return MessageDisplayCard(
            displayText: L10n.of(context)
                .messageNotInTargetLang, // Pass the display text,
          );
        }
        if (overLayController.selectedSpan == null) {
          return null;
        }
        return PracticeActivityCard(
          pangeaMessageEvent: pangeaMessageEvent,
          overlayController: overLayController,
        );
      default:
        debugger(when: kDebugMode);
        ErrorHandler.logError(
          e: "Invalid toolbar mode",
          s: StackTrace.current,
          data: {"newMode": overLayController.toolbarMode},
        );
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (![MessageTypes.Text, MessageTypes.Audio].contains(
      pangeaMessageEvent.event.messageType,
    )) {
      return const SizedBox();
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.all(
          Radius.circular(AppConfig.borderRadius),
        ),
      ),
      constraints: const BoxConstraints(
        maxHeight: AppConfig.toolbarMaxHeight,
        minWidth: AppConfig.toolbarMinWidth,
        minHeight: AppConfig.toolbarMinHeight,
        // maxWidth is set by MessageSelectionOverlay
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSize(
            duration: FluffyThemes.animationDuration,
            child: toolbarContent(context),
          ),
        ],
      ),
    );
  }
}
