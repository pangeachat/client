import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/word_zoom_activity_button.dart';

class LemmaEmojiRow extends StatelessWidget {
  final ConstructIdentifier cId;
  final VoidCallback onTap;
  final bool isSelected;

  const LemmaEmojiRow({
    required this.cId,
    required this.onTap,
    this.isSelected = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final emojis = cId.userSetEmoji;

    return Row(
      children: [
        for (var i = 0; i < 3; i++)
          i < emojis.length
              ? GestureDetector(
                  onTap: onTap,
                  child: Container(
                    child: Text(emojis[i]),
                  ),
                )
              : WordZoomActivityButton(
                  icon: Icon(
                    Icons.add_reaction_outlined,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  isSelected: isSelected,
                  onPressed: onTap,
                  opacity: isSelected ? 1 : 0.4,
                  tooltip: MessageMode.wordEmoji.title(context),
                ),
      ],
    );
  }
}
