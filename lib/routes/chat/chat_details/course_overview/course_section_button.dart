import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// A course-page section's "See all" link — label + chevron, opening the
/// section's full subpage within the card.
///
/// It rides its section header's trailing slot (#8744), where it sits beside
/// the title rather than below the section's content: a priority action, in
/// the same place for every section, reachable without scrolling the section
/// first. The header places it, so the button carries no padding or alignment
/// of its own.
///
/// Every section's link reads the same "See all" — the section it belongs to
/// is already named by the header beside it, so repeating it in the label
/// only adds words. A screen reader gets no such adjacency, which is why
/// [section] names it in the accessible name instead: four buttons that all
/// spoke "See all" would be untellable apart.
class CourseSectionButton extends StatelessWidget {
  /// The section's display title, for the accessible name only.
  final String section;
  final VoidCallback onPressed;

  const CourseSectionButton({
    required this.section,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        // Tighter than Material's 12, so the link sits close to the section
        // edge rather than floating off it.
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        textStyle: Theme.of(context).textTheme.bodyMedium,
        visualDensity: VisualDensity.compact,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A long localization plus the button's own padding can outrun a
          // narrow course column, so the label wraps inside the width the
          // header allows it rather than overflowing the header's row.
          Flexible(
            child: Text(
              l10n.seeAll,
              semanticsLabel: l10n.seeAllSection(section),
            ),
          ),
          const Icon(Icons.chevron_right, size: 18.0),
        ],
      ),
    );
  }
}
