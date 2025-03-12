import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/message_audio_choice_item.dart';
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
                .map(
                  (wordForm) => MessageAudioChoiceItem(
                    wordForm: wordForm,
                    isGold: overlayController.selectedToken != null
                        ? overlayController.selectedToken!.text.content ==
                            wordForm
                        : null,
                    onTap: () =>
                        overlayController.onWordAudioChoiceSelect(wordForm),
                    isSelected: overlayController.selectedWordAudioSurfaceForm
                            ?.toLowerCase() ==
                        wordForm.toLowerCase(),
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
