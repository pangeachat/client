import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/message_audio_choice_item.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_audio_card.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';

class MessageAudioChoice extends StatelessWidget {
  final MessageOverlayController overlayController;
  final PangeaMessageEvent pangeaMessageEvent;

  const MessageAudioChoice({
    super.key,
    required this.overlayController,
    required this.pangeaMessageEvent,
  });

  int selectedIndex(String choice) =>
      overlayController.messageWordFormsForDisplay
          .indexWhere((element) => element == choice);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          MessageAudioCard(
            messageEvent: pangeaMessageEvent,
            overlayController: overlayController,
            setIsPlayingAudio: overlayController.setIsPlayingAudio,
          ),
          const SizedBox(height: 8.0),
          Text(
            "${overlayController.messageWordFormsForDisplay.length} word forms left to match",
          ),
          const SizedBox(height: 8.0),
          Wrap(
            children: overlayController.messageWordFormsForDisplay
                .mapIndexed(
                  (index, wordForm) => MessageAudioChoiceItem(
                    wordForm: wordForm,
                    isGold: overlayController.selectedToken != null
                        ? overlayController.selectedToken!.text.content ==
                            wordForm
                        : null,
                    onTap: () => overlayController.onChoiceSelect(index),
                    isSelected:
                        overlayController.selectedChoices.contains(index),
                    ttsController: overlayController
                        .widget.chatController.choreographer.tts,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
