import 'package:collection/collection.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/message_choice_item.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_audio_card.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:flutter/material.dart';

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
          const SizedBox(height: 8.0),
          MessageAudioCard(
            messageEvent: pangeaMessageEvent,
            overlayController: overlayController,
            setIsPlayingAudio: overlayController.setIsPlayingAudio,
          ),
          const SizedBox(height: 8.0),
          Wrap(
            children: overlayController.messageWordFormsForDisplay
                .mapIndexed(
                  (index, wordForm) => MessageChoiceItem(
                    content: const Icon(
                      Icons.volume_up,
                    ),
                    onTap: () => overlayController.onChoiceSelect(index),
                    isSelected:
                        overlayController.selectedChoices.contains(index),
                    isGold: overlayController.selectedToken != null
                        ? overlayController.selectedToken!.text.content
                                .toLowerCase() ==
                            wordForm.toLowerCase()
                        : null,
                    audioContent: wordForm,
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
