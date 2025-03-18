import 'package:collection/collection.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/message_choice_item.dart';
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
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 2.0, // Adjust spacing between items
            runSpacing: 2.0, // Adjust spacing between rows
            children: overlayController.messageMeaningsForDisplay
                // .take(totalEmojiChoicesToDisplay)
                .mapIndexed(
              (int index, String meaning) {
                return MessageChoiceItem(
                  content: Text(
                    meaning,
                    style: const TextStyle(fontSize: 26),
                  ),
                  contentOpacity: 1,
                  onTap: () => overlayController.onChoiceSelect(index),
                  isSelected: overlayController.selectedChoices.contains(index),
                  isGold: overlayController.selectedToken != null
                      ? overlayController
                              .messageLemmaInfos![overlayController
                                  .selectedToken?.vocabConstructID]
                              ?.meaning ==
                          meaning
                      : null,
                  onDoubleTap: () => {},
                  onLongPress: () => {},
                );
              },
            ).toList(),
          ),
        ],
      ),
    );
  }
}
