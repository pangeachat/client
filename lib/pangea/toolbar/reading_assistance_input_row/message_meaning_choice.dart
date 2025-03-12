import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/choreographer/widgets/choice_array.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:flutter/material.dart';

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
          ChoicesArray(
            isLoading: overlayController.messageLemmaInfos == null,
            choices: overlayController.messageMeaningsForDisplay
                .map(
                  (choice) => Choice(
                    color: overlayController.selectedMeanings?.toLowerCase() ==
                            choice.toLowerCase()
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
            onPressed: (choice, index) =>
                overlayController.onMessageMeaningChoiceSelect(
              choice,
            ),
            originalSpan: overlayController.selectedToken?.lemma.text ?? "",
            uniqueKeyForLayerLink: (int index) => "emojiChoice$index",
            // @ggurdin: what to do with this?
            selectedChoiceIndex: null,
            tts: null,
            fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize ??
                AppConfig.messageFontSize + 2,
            enableMultiSelect: false,
            // @ggurdin: should this always be true?
            isActive: true,
            overflowMode: OverflowMode.wrap,
          ),
        ],
      ),
    );
  }
}
