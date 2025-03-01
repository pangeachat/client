import 'package:fluffychat/config/app_emojis.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/emoji_choice_item.dart';
import 'package:flutter/material.dart';

class EmojiMessageChoice extends StatelessWidget {
  final List<PangeaToken>? tokens;
  final ChatController controller;
  final void Function(PangeaToken) onTap;

  const EmojiMessageChoice({
    super.key,
    required this.tokens,
    required this.controller,
    required this.onTap,
  });

  Widget emojiView(PangeaToken token) {
    if (!token.lemma.saveVocab) {
      return EmojiChoiceItem(
        topContent: token.text.content,
        content: token.text.content,
        onTap: () => onTap(token),
        isSelected: false,
      );
    }

    final emoji = token.getEmoji();

    if (emoji == null) {
      return Opacity(
        opacity: 0.1,
        child: EmojiChoiceItem(
          topContent: token.text.content,
          content: token.xpEmoji,
          onTap: () => onTap(token),
          isSelected: false,
        ),
      );
    }

    return EmojiChoiceItem(
      topContent: token.text.content,
      content: emoji,
      onTap: () => onTap(token),
      isSelected: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: tokens == null || tokens!.isEmpty
          ? AppEmojis.emojis
              .map(
                (emoji) => EmojiChoiceItem(
                  content: emoji,
                  onTap: () => controller.sendEmojiAction(emoji),
                  isSelected: false,
                ),
              )
              .toList()
          : tokens!
              .where((token) => token.lemma.saveVocab)
              .map((token) => emojiView(token))
              .toList(),
    );
  }
}
