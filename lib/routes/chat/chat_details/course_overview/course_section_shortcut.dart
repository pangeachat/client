import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/widgets/bold_tonal_button.dart';

/// A course-page section's shortcut — the one-tap action a section offers
/// beside its "See all" (create a chat, invite a member), riding the header's
/// action row with it (#8744).
///
/// A tonal circle rather than a bare glyph (#8815): as a plain icon it read as
/// decoration, and in the Chats section it was the twin of the create-chat
/// tile's leading glyph one row down — one a button, one not. The bold
/// pressable style the "See all" beside it and the Mission card's Practice
/// wear (#9420 prototype), so the page's secondary actions read as one set.
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
  Widget build(BuildContext context) => BoldTonalButton(
    icon: icon,
    label: showLabel ? label : null,
    semanticsLabel: label,
    onPressed: onPressed,
  );
}
