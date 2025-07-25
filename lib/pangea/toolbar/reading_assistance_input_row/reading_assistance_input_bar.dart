import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_mode_locked_card.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_translation_card.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/practice_activity_card.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_mode_buttons.dart';

const double minContentHeight = 120;

class ReadingAssistanceInputBar extends StatelessWidget {
  final ChatController controller;
  final MessageOverlayController overlayController;

  const ReadingAssistanceInputBar(
    this.controller,
    this.overlayController, {
    super.key,
  });

  Widget barContent(BuildContext context) {
    Widget? content;
    final target =
        overlayController.toolbarMode.associatedActivityType != null &&
                overlayController.pangeaMessageEvent != null
            ? overlayController.practiceSelection?.getSelection(
                overlayController.toolbarMode.associatedActivityType!,
                overlayController.selectedMorph?.token,
                overlayController.selectedMorph?.morph,
              )
            : null;

    if (overlayController.pangeaMessageEvent?.isAudioMessage == true) {
      return const SizedBox();
      // return ReactionsPicker(controller);
    } else {
      switch (overlayController.toolbarMode) {
        case MessageMode.messageSpeechToText:
        case MessageMode.practiceActivity:
        case MessageMode.wordZoom:
        case MessageMode.noneSelected:
        case MessageMode.messageMeaning:
          //TODO: show all emojis for the lemmas and allow sending normal reactions
          content = Text(
            L10n.of(context).choosePracticeMode,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          );

        case MessageMode.messageTranslation:
          if (overlayController.isTranslationUnlocked) {
            content = MessageTranslationCard(
              messageEvent: overlayController.pangeaMessageEvent!,
            );
          } else {
            content = MessageModeLockedCard(controller: overlayController);
          }

        case MessageMode.wordEmoji:
        case MessageMode.wordMeaning:
        case MessageMode.listening:
          if (target != null) {
            content = PracticeActivityCard(
              pangeaMessageEvent: overlayController.pangeaMessageEvent!,
              targetTokensAndActivityType: target,
              overlayController: overlayController,
            );
          } else {
            content = Text(
              L10n.of(context).allDone,
              textAlign: TextAlign.center,
            );
          }
        case MessageMode.wordMorph:
          if (target != null) {
            content = PracticeActivityCard(
              pangeaMessageEvent: overlayController.pangeaMessageEvent!,
              targetTokensAndActivityType: target,
              overlayController: overlayController,
            );
          } else {
            content = Center(
              child: Text(
                L10n.of(context).selectForGrammar,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            );
          }
      }
    }

    return content;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PracticeModeButtons(
          overlayController: overlayController,
        ),
        Material(
          child: Container(
            padding: const EdgeInsets.all(8.0),
            alignment: Alignment.center,
            constraints: BoxConstraints(
              minHeight: minContentHeight,
              maxHeight: AppConfig.readingAssistanceInputBarHeight,
              maxWidth: overlayController.maxWidth,
            ),
            child: AnimatedSize(
              duration: const Duration(
                milliseconds: AppConfig.overlayAnimationDuration,
              ),
              child: SingleChildScrollView(
                child: barContent(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
