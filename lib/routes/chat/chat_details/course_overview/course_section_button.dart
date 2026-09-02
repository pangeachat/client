import 'package:flutter/material.dart';

/// A course-page section's "see all" button: section glyph, label, chevron —
/// opening the section's full subpage within the card.
///
/// It rides its section header's trailing slot (#8744), where it sits beside
/// the title rather than below the section's content: a priority action, in
/// the same place for every section, reachable without scrolling the section
/// first. The header places it, so the button carries no padding or alignment
/// of its own.
///
/// Filled rather than primary-colored text, so it doesn't read the same as
/// the current Mission text sitting right above it (#8475) — the color is the
/// button's fill, and the pill shape is what marks it pressable. The leading
/// glyph and compact density match the Participants section's invite button,
/// which shares this slot, so the section actions read as one family (#8744).
class CourseSectionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData icon;

  const CourseSectionButton({
    required this.label,
    required this.onPressed,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        // Tighter than Material's 24, so the pill stays close to its
        // label rather than reading as a full-width action.
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        textStyle: Theme.of(context).textTheme.bodyMedium,
        visualDensity: VisualDensity.compact,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6.0,
        children: [
          Icon(icon, size: 16.0),
          // A long localization plus the button's own padding can outrun a
          // narrow course column, so the label wraps inside the width the
          // header allows it rather than overflowing the header's row.
          Flexible(child: Text(label)),
          const Icon(Icons.chevron_right, size: 18.0),
        ],
      ),
    );
  }
}
