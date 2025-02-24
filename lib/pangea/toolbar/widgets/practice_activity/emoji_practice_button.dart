import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/word_zoom_activity_button.dart';
import 'package:flutter/material.dart';

class EmojiPracticeButton extends StatelessWidget {
  final PangeaToken token;
  final VoidCallback onPressed;
  final bool isSelected;

  const EmojiPracticeButton({
    required this.token,
    required this.onPressed,
    this.isSelected = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final emoji = token.getEmoji();
    return WordZoomActivityButton(
      icon: emoji == null
          ? const Icon(Icons.add_reaction_outlined)
          : Text(
              emoji,
              style: const TextStyle(fontSize: 24),
            ),
      isSelected: isSelected,
      onPressed: onPressed,
    );
  }
}
