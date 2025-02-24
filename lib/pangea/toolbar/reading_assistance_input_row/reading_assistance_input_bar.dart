import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/analytics_misc/message_analytics_controller.dart';
import 'package:fluffychat/pangea/analytics_misc/put_analytics_controller.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/enums/activity_type_enum.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/reading_assistance_input_bar_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/practice_activity_card.dart';
import 'package:flutter/material.dart';

import 'message_emoji_choice_row.dart';

class ReadingAssistanceInputBar extends StatelessWidget {
  final ChatController controller;
  final MessageOverlayController? overlayController;

  ReadingAssistanceModeEnum get mode {
    // this surprisingly happens
    // it seems the controller is not yet initialized
    if (overlayController == null) {
      return ReadingAssistanceModeEnum.messageEmojiChoice;
    }

    return overlayController!.inputBarMode;
  }

  const ReadingAssistanceInputBar(
    this.controller,
    this.overlayController, {
    super.key,
  });

  PangeaToken? get token => overlayController?.selectedToken;

  Widget barContent(BuildContext context) {
    switch (mode) {
      // message meaning will not use the input bar (for now at least)
      // maybe we move some choices there later
      case ReadingAssistanceModeEnum.messageMeaning:
      case ReadingAssistanceModeEnum.messageEmojiChoice:
        return MessageEmojiChoiceRow(
          tokens: overlayController
                  ?.pangeaMessageEvent?.messageDisplayRepresentation?.tokens ??
              [],
          controller: controller,
          overlayController: overlayController,
        );
      case ReadingAssistanceModeEnum.wordEmojiChoice:
        return PracticeActivityCard(
          pangeaMessageEvent: overlayController!.pangeaMessageEvent!,
          targetTokensAndActivityType: TargetTokensAndActivityType(
            tokens: [token!],
            activityType: ActivityTypeEnum.emoji,
          ),
          overlayController: overlayController!,
          location: AnalyticsUpdateOrigin.inputBar,
        );
      case ReadingAssistanceModeEnum.wordMeaningChoice:
        return PracticeActivityCard(
          pangeaMessageEvent: overlayController!.pangeaMessageEvent!,
          targetTokensAndActivityType: TargetTokensAndActivityType(
            tokens: [token!],
            activityType: ActivityTypeEnum.wordMeaning,
          ),
          overlayController: overlayController!,
          location: AnalyticsUpdateOrigin.inputBar,
        );
      case ReadingAssistanceModeEnum.morph:
        return PracticeActivityCard(
          pangeaMessageEvent: overlayController!.pangeaMessageEvent!,
          targetTokensAndActivityType: TargetTokensAndActivityType(
            tokens: [token!],
            activityType: ActivityTypeEnum.wordMeaning,
          ),
          overlayController: overlayController!,
          location: AnalyticsUpdateOrigin.inputBar,
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
