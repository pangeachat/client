import 'package:flutter/material.dart';

import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_header.dart';

/// A course-page section's shortcut — the one-tap action a section offers
/// beside its "See all" (create a chat, invite a member), riding the header's
/// action row with it (#8744).
///
/// A tonal circle rather than a bare glyph (#8815): as a plain icon it read as
/// decoration, and in the Chats section it was the twin of the create-chat
/// tile's leading glyph one row down — one a button, one not. The fill is the
/// one the "See all" beside it wears, so the two read as one row of actions.
class CourseSectionShortcut extends StatelessWidget {
  final IconData icon;

  /// The accessible name too — the control has no visible label.
  final String tooltip;
  final VoidCallback onPressed;

  const CourseSectionShortcut({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      icon: Icon(icon),
      // The header's own section glyph, so the row's icons match.
      iconSize: CourseSectionHeader.iconSize,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}
