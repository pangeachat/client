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

  /// The tooltip and accessible name, and the visible label when [showLabel].
  final String label;

  /// For a shortcut people miss as a bare icon (#9492).
  final bool showLabel;

  final VoidCallback onPressed;

  const CourseSectionShortcut({
    required this.icon,
    required this.label,
    required this.showLabel,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // The header's own section glyph size, so the row's icons match.
    final glyph = Icon(icon, size: CourseSectionHeader.iconSize);
    if (!showLabel) {
      return IconButton.filledTonal(
        icon: glyph,
        tooltip: label,
        onPressed: onPressed,
      );
    }
    return Tooltip(
      message: label,
      // The visible label already names the button for a screen reader.
      excludeFromSemantics: true,
      child: FilledButton.tonalIcon(
        icon: glyph,
        label: Text(label),
        onPressed: onPressed,
      ),
    );
  }
}
