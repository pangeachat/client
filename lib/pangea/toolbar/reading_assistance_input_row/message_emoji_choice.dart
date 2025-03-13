import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/message_emoji_choice_item.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class MessageEmojiChoice extends StatelessWidget {
  final ChatController controller;
  final MessageOverlayController overlayController;

  const MessageEmojiChoice({
    super.key,
    required this.controller,
    required this.overlayController,
  });

  Future<void> redactReaction(BuildContext context, String emoji) {
    if (!context.mounted) {
      return Future.value();
    }
    final evt = allReactionEvents.firstWhereOrNull(
      (e) =>
          e.senderId == e.room.client.userID &&
          e.content.tryGetMap('m.relates_to')?['key'] == emoji,
    );
    if (evt != null) {
      return showFutureLoadingDialog(
        context: context,
        future: () => evt.redactEvent(),
      );
    }
    return Future.value();
  }

  Iterable<Event> get allReactionEvents => controller.selectedEvents.first
      .aggregatedEvents(
        controller.timeline!,
        RelationshipTypes.reaction,
      )
      .where(
        (event) =>
            event.senderId == event.room.client.userID &&
            event.type == 'm.reaction',
      );

  bool alreadyInReactions(String emoji) {
    for (final event in allReactionEvents) {
      try {
        if (event.content.tryGetMap('m.relates_to')!['key'] == emoji) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  void onDoubleTapOrLongPress(BuildContext context, String emoji) {
    if (alreadyInReactions(emoji)) {
      redactReaction(context, emoji);
    } else {
      controller.sendEmojiAction(emoji);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Column(
        children: [
          Text(
            "${overlayController.messageEmojisForDisplay.length} emojis left to sort",
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 2.0, // Adjust spacing between items
            runSpacing: 0.0, // Adjust spacing between rows
            children: overlayController.messageEmojisForDisplay
                .map(
                  (emoji) => MessageEmojiChoiceItem(
                    textSize: 26,
                    content: emoji,
                    onTap: () =>
                        overlayController.onMessageEmojiChoiceSelect(emoji),
                    isSelected:
                        overlayController.selectedEmojis.contains(emoji),
                    onDoubleTap: () => {},
                    onLongPress: () => {},
                    token: null,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
