import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/message_morph_choice_item.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';

class MessageMorphChoice extends StatelessWidget {
  final MessageOverlayController overlayController;
  final PangeaMessageEvent pangeaMessageEvent;

  const MessageMorphChoice({
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
            "${overlayController.messageMorphTagsForDisplay.length} grammar tags left to match",
          ),
          const SizedBox(height: 8.0),
          Wrap(
            children: overlayController.messageMorphTagsForDisplay
                .map(
                  (cId) => MessageMorphChoiceItem(
                    cId: cId,
                    onTap: () => overlayController.onMorphChoiceSelect(cId),
                    isSelected:
                        overlayController.selectedMorphTags.contains(cId),
                    isGold: overlayController.selectedToken?.morphConstructIds
                        .contains(cId),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
