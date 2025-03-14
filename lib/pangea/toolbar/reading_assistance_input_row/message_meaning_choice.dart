import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/choreographer/widgets/choice_array.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_translation_card.dart';

class MessageMeaningChoice extends StatelessWidget {
  final MessageOverlayController overlayController;
  final PangeaMessageEvent pangeaMessageEvent;

  const MessageMeaningChoice({
    super.key,
    required this.overlayController,
    required this.pangeaMessageEvent,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          const SizedBox(height: 8.0),
          Text(
            "${overlayController.messageMeaningsForDisplay.length} meanings left to match",
          ),
          const SizedBox(height: 8.0),
          overlayController.messageMeaningsForDisplay.isNotEmpty ||
                  overlayController.messageLemmaInfos == null
              ? ChoicesArray(
                  isLoading: overlayController.messageLemmaInfos == null,
                  choices: overlayController.messageMeaningsForDisplay
                      .mapIndexed(
                        (index, choice) => Choice(
                          color:
                              overlayController.selectedChoices.contains(index)
                                  ? AppConfig.primaryColor
                                  : Colors.transparent,
                          text: choice,
                          // TODO: probably move to overlayController
                          isGold: overlayController
                                  .messageLemmaInfos?[overlayController
                                      .selectedToken?.vocabConstructID.string]
                                  ?.meaning
                                  .toLowerCase() ==
                              choice.toLowerCase(),
                        ),
                      )
                      .toList(),
                  //TODO: make sure the indices match and choiceArray doesn't shuffle or something
                  onPressed: (choice, index) =>
                      overlayController.onChoiceSelect(index),
                  originalSpan:
                      overlayController.selectedToken?.lemma.text ?? "",
                  uniqueKeyForLayerLink: (int index) => "emojiChoice$index",
                  selectedChoiceIndex:
                      overlayController.selectedChoices.isNotEmpty
                          ? overlayController.selectedChoices.first
                          : null,
                  tts: null,
                  fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize ??
                      AppConfig.messageFontSize + 2,
                  enableMultiSelect: false,
                  // @ggurdin: should this always be true?
                  isActive: true,
                  overflowMode: OverflowMode.wrap,
                )
              : MessageTranslationCard(messageEvent: pangeaMessageEvent),
        ],
      ),
    );
  }
}
