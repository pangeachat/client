import 'package:collection/collection.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/message_emoji_choice_item.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

const int totalEmojiChoicesToDisplay = 7;

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
          const SizedBox(
            height: 8,
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 2.0, // Adjust spacing between items
            runSpacing: 2.0, // Adjust spacing between rows
            children: overlayController.messageEmojisForDisplay
                // .take(totalEmojiChoicesToDisplay)
                .mapIndexed(
              (int index, String emoji) {
                final alreadyChosenForLemma = overlayController
                        .selectedToken?.vocabConstructID.userSetEmoji
                        .contains(emoji) ??
                    false;
                final isSelected =
                    overlayController.selectedChoices.contains(index);

                return MessageEmojiChoiceItem(
                  textSize: 26,
                  content: emoji,
                  contentOpacity:
                      alreadyChosenForLemma && !isSelected ? 0.1 : 1,
                  onTap: () => !alreadyChosenForLemma
                      ? overlayController.onChoiceSelect(index)
                      : null,
                  isSelected: overlayController.selectedChoices.contains(index),
                  isGold: overlayController
                      .messageLemmaInfos?[
                          overlayController.selectedToken?.vocabConstructID]
                      ?.emoji
                      .contains(emoji),
                  onDoubleTap: () => {},
                  onLongPress: () => {},
                  token: null,
                );
              },
            ).toList(),
          ),
          // a stack of the remaining emojis looking like a stack of cards
          // Container(
          //   child: Stack(
          //     children: overlayController.messageEmojisForDisplay.isNotEmpty
          //         //     Container(
          //         //       height: emojiButtonSize.height,
          //         //       width: emojiButtonSize.width,
          //         //       decoration: emojiButtonDecoration.copyWith(
          //         //         color: Theme.of(context).colorScheme.primary,
          //         //         boxShadow: [
          //         //           const BoxShadow(
          //         //             color: Colors.black,
          //         //             spreadRadius: 1,
          //         //             blurRadius: 2,
          //         //             offset: Offset(1, 1),
          //         //           ),
          //         //         ],
          //         //       ),
          //         //       alignment: Alignment.center,
          //         //       child: Icon(
          //         //         Icons.add_reaction_outlined,
          //         //         color: Theme.of(context).colorScheme.primary,
          //         //       ),
          //         //     ),
          //         //   ]
          //         ? [
          //             for (var i = 0;
          //                 // i <
          //                 //     overlayController
          //                 //             .messageEmojisForDisplay.length -
          //                 //         totalEmojiChoicesToDisplay;
          //                 i < 3;
          //                 i++)
          //               Container(
          //                 height: emojiButtonSize.height,
          //                 width: emojiButtonSize.width,
          //                 decoration: emojiButtonDecoration.copyWith(
          //                   color: Theme.of(context).colorScheme.primary,
          //                   boxShadow: [
          //                     const BoxShadow(
          //                       color: Colors.black,
          //                       spreadRadius: 1,
          //                       blurRadius: 2,
          //                       offset: Offset(1, 1),
          //                     ),
          //                   ],
          //                 ),
          //                 alignment: Alignment.center,
          //                 child: i == 0
          //                     ? Icon(
          //                         Icons.add_reaction_outlined,
          //                         color: Theme.of(context)
          //                             .colorScheme
          //                             .surfaceContainer,
          //                       )
          //                     : const SizedBox(),
          //               ),
          //           ].reversed.toList()
          //         : [
          //             Container(
          //               height: emojiButtonSize.height,
          //               width: emojiButtonSize.width,
          //               decoration: emojiButtonDecoration.copyWith(
          //                 color: Theme.of(context)
          //                     .colorScheme
          //                     .primary
          //                     .withAlpha(40),
          //                 boxShadow: [
          //                   BoxShadow(
          //                     color: Theme.of(context).colorScheme.primary,
          //                     spreadRadius: 1,
          //                     blurRadius: 2,
          //                     offset: const Offset(1, 0),
          //                   ),
          //                 ],
          //               ),
          //               alignment: Alignment.center,
          //               child: Icon(
          //                 Icons.add_reaction_outlined,
          //                 color: Theme.of(context).colorScheme.primary,
          //               ),
          //             ),
          //           ],
          //   ),
          // ),
        ],
      ),
    );
  }
}
