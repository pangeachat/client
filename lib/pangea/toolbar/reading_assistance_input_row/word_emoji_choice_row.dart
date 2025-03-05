// PangeaReactionsPicker replaces regular EmojiPicker
// When no word is selected
// Show a list of LanguageLearningEmojiWidgets. This list is produced by the pangea_message_event_model.dart.
// For each token in the messageDisplayTokens (if null then regular emojis):
// If save_vocab, show
// 1) token.xpEmoji for new words that you haven't chosen an emoji for OR
// 2) once you’ve selected an emoji, the seed grows into a little sprout before being covered by the selected emoji with a popping sound OR
// 3) the emoji you selected previously.
// Else show
// token.text.content.
// This helps remind the user to interpret the message just via the images. It helps remind them what it means in visuals rather than words.
// It mirrors the green highlights which enhances accessibility.
// When a word is selected,
// The bottom bar shows the selection of emojis that you can choose for that word.
// Only if the messageDisplayTokens are null do show the regular emojis. They suck anyway.

import 'package:collection/collection.dart';
import 'package:fluffychat/pangea/toolbar/models/practice_activity_model.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/emoji_choice_item.dart';
import 'package:flutter/material.dart';

class WordEmojiChoiceRow extends StatelessWidget {
  const WordEmojiChoiceRow({
    super.key,
    required this.onTap,
    required this.activity,
    required this.selectedChoiceIndex,
  });

  final PracticeActivityModel activity;
  final void Function(String, int) onTap;
  final int? selectedChoiceIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: activity.content.choices
          .mapIndexed(
            (index, emoji) => EmojiChoiceItem(
              content: emoji,
              onTap: () => onTap(emoji, index),
              isSelected: selectedChoiceIndex != null
                  ? selectedChoiceIndex == index
                  : activity.targetTokens?.first.getEmoji() == emoji,
              onDoubleTap: null,
              onLongPress: null,
            ),
          )
          .toList(),
    );
  }
}
