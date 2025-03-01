import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/analytics_misc/message_analytics_controller.dart';
import 'package:fluffychat/pangea/analytics_misc/put_analytics_controller.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/enums/activity_type_enum.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/practice_activity_card.dart';
import 'package:flutter/material.dart';

import 'message_emoji_choice_row.dart';

class ReadingAssistanceInputBar extends StatelessWidget {
  final ChatController controller;
  final MessageOverlayController? overlayController;

  const ReadingAssistanceInputBar(
    this.controller,
    this.overlayController, {
    super.key,
  });

  PangeaToken? get token => overlayController?.selectedToken;

  PracticeActivityCard practiceActivityCard(ActivityTypeEnum a) =>
      PracticeActivityCard(
        pangeaMessageEvent: overlayController!.pangeaMessageEvent!,
        targetTokensAndActivityType: TargetTokensAndActivityType(
          tokens: [token!],
          activityType: a,
        ),
        overlayController: overlayController!,
        morphFeature: a == ActivityTypeEnum.morphId
            ? overlayController?.selectedMorphFeature ??
                overlayController
                    ?.selectedToken?.nextMorphFeatureEligibleForActivity ??
                "pos"
            : null,
        location: AnalyticsUpdateOrigin.inputBar,
      );

  Widget barContent(BuildContext context) {
    if (token == null) {
      return MessageEmojiChoiceRow(
        tokens: overlayController
                ?.pangeaMessageEvent?.messageDisplayRepresentation?.tokens ??
            [],
        controller: controller,
        overlayController: overlayController,
      );
    }

    switch (overlayController!.toolbarMode) {
      // message meaning will not use the input bar (for now at least)
      // maybe we move some choices there later
      case MessageMode.messageMeaning:
      case MessageMode.messageTranslation:
      case MessageMode.messageTextToSpeech:
      case MessageMode.messageSpeechToText:
      case MessageMode.practiceActivity:
      case MessageMode.wordZoom:
      case MessageMode.noneSelected:
        return MessageEmojiChoiceRow(
          tokens: overlayController
                  ?.pangeaMessageEvent?.messageDisplayRepresentation?.tokens ??
              [],
          controller: controller,
          overlayController: overlayController,
        );

      case MessageMode.wordEmoji:
        return practiceActivityCard(ActivityTypeEnum.emoji);

      case MessageMode.wordMeaning:
        return practiceActivityCard(ActivityTypeEnum.wordMeaning);

      case MessageMode.wordMorph:
        return practiceActivityCard(ActivityTypeEnum.morphId);
    }
  }

  @override
  Widget build(BuildContext context) {
    // @ggurdin when does this happen?
    if (controller.showEmojiPicker) return const SizedBox.shrink();

    final display = controller.editEvent == null &&
        controller.replyEvent == null &&
        controller.room.canSendDefaultMessages &&
        controller.selectedEvents.isNotEmpty;

    if (!display) {
      return const SizedBox.shrink();
    }

    return Flexible(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        // @ggurdin - redundant no?
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: barContent(context),
            ),
          ),
        ],
      ),
    );
  }
}
