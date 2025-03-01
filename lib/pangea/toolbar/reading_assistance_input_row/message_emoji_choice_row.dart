import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_emojis.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/emoji_choice_item.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class MessageEmojiChoiceRow extends StatelessWidget {
  final List<PangeaToken>? tokens;
  final ChatController controller;
  final MessageOverlayController? overlayController;

  const MessageEmojiChoiceRow({
    super.key,
    required this.tokens,
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

  List<Widget> standardEmojiChoices(BuildContext context) => AppEmojis.emojis
      .map(
        (emoji) => EmojiChoiceItem(
          content: emoji,
          onTap: () => alreadyInReactions(emoji)
              ? redactReaction(context, emoji)
              : controller.sendEmojiAction(emoji),
          isSelected: false,
        ),
      )
      .toList();

  List<Widget> get perTokenEmoji =>
      tokens!.where((token) => token.lemma.saveVocab).map((token) {
        if (!token.lemma.saveVocab) {
          return EmojiChoiceItem(
            topContent: token.text.content,
            content: token.text.content,
            onTap: () => overlayController!.onClickOverlayMessageToken(token),
            isSelected: overlayController?.isTokenSelected(token) ?? false,
          );
        }

        final emoji = token.getEmoji();

        if (emoji == null) {
          return Opacity(
            opacity: 0.1,
            child: EmojiChoiceItem(
              topContent: token.text.content,
              content: token.xpEmoji,
              onTap: () => overlayController!.onClickOverlayMessageToken(token),
              isSelected: overlayController?.isTokenSelected(token) ?? false,
            ),
          );
        }

        return EmojiChoiceItem(
          topContent: token.text.content,
          content: emoji,
          onTap: () => overlayController!.onClickOverlayMessageToken(token),
          isSelected: overlayController?.isTokenSelected(token) ?? false,
        );
      }).toList();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: tokens == null || tokens!.isEmpty
          ? standardEmojiChoices(context)
          : perTokenEmoji,
    );
  }
}
