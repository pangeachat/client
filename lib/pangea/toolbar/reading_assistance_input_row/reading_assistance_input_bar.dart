import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/analytics_misc/message_analytics_controller.dart';
import 'package:fluffychat/pangea/analytics_misc/put_analytics_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/enums/activity_type_enum.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/message_audio_choice.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/message_emoji_choice.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/message_meaning_choice.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/message_morph_choice.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_mode_locked_card.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_translation_card.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/practice_activity_card.dart';

class ReadingAssistanceInputBar extends StatelessWidget {
  final ChatController controller;
  final MessageOverlayController overlayController;

  const ReadingAssistanceInputBar(
    this.controller,
    this.overlayController, {
    super.key,
  });

  PangeaToken? get token => overlayController.selectedToken;

  PracticeActivityCard getPracticeActivityCard(
    ActivityTypeEnum a, [
    String? morphFeature,
  ]) {
    if (a == ActivityTypeEnum.morphId && morphFeature == null) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        m: "morphFeature null with activityType of morphId in getPracticeActivityCard",
        s: StackTrace.current,
        data: token?.toJson() ?? {},
      );
      morphFeature = "pos";
    }
    return PracticeActivityCard(
      pangeaMessageEvent: overlayController.pangeaMessageEvent!,
      targetTokensAndActivityType: TargetTokensAndActivityType(
        tokens: [token!],
        activityType: a,
      ),
      overlayController: overlayController,
      morphFeature: morphFeature,
      location: AnalyticsUpdateOrigin.inputBar,
    );
  }

  Widget barContent(BuildContext context) {
    switch (overlayController.toolbarMode) {
      // message meaning will not use the input bar (for now at least)
      // maybe we move some choices there later
      case MessageMode.messageSpeechToText:
      case MessageMode.practiceActivity:
      case MessageMode.wordZoom:
      case MessageMode.wordEmoji:
      case MessageMode.noneSelected:
        return MessageEmojiChoice(
          controller: controller,
          overlayController: overlayController,
        );

      case MessageMode.messageTextToSpeech:
        return MessageAudioChoice(
          overlayController: overlayController,
          pangeaMessageEvent: overlayController.pangeaMessageEvent!,
        );

      case MessageMode.messageTranslation:
        if (overlayController.isTranslationUnlocked) {
          return MessageTranslationCard(
            messageEvent: overlayController.pangeaMessageEvent!,
          );
        } else {
          return Container(
            constraints: const BoxConstraints.expand(),
            child: MessageModeLockedCard(controller: overlayController),
          );
        }

      case MessageMode.messageMeaning:
      case MessageMode.wordMeaning:
        return MessageMeaningChoice(
          overlayController: overlayController,
          pangeaMessageEvent: overlayController.pangeaMessageEvent!,
        );

      case MessageMode.wordMorph:
        return MessageMorphChoice(
          overlayController: overlayController,
          pangeaMessageEvent: overlayController.pangeaMessageEvent!,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (controller.showEmojiPicker) return const SizedBox.shrink();

    final display = controller.editEvent == null &&
        controller.replyEvent == null &&
        controller.room.canSendDefaultMessages &&
        controller.selectedEvents.isNotEmpty;

    if (!display) {
      return const SizedBox.shrink();
    }

    return Expanded(
      child: Container(
        height: AppConfig.readingAssistanceInputBarHeight,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.all(
            Radius.circular(8.0),
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          children: [
            // Row(
            //   mainAxisAlignment: MainAxisAlignment.center,
            //   children: overlayController.toolbarMode
            //       .messageModeChoiceLevel(
            //         overlayController,
            //         overlayController.pangeaMessageEvent!,
            //       )
            //       .toList(),
            // ),
            Expanded(child: barContent(context)),
          ],
        ),
      ),
    );
  }
}
