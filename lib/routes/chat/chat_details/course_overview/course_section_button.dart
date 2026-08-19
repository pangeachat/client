import 'package:flutter/material.dart';

/// A course-page section's "see all" button: label + chevron, opening the
/// section's full subpage within the card.
///
/// Filled rather than primary-colored text, so it doesn't read the same as
/// the current Mission text sitting right above it (#8475) — the color is the
/// button's fill, and the pill shape is what marks it pressable.
class CourseSectionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  /// An indicator after the chevron, inside the same button — e.g. the ping
  /// badge telling the learner the pinged activity is on the subpage.
  final Widget? trailing;

  const CourseSectionButton({
    required this.label,
    required this.onPressed,
    this.trailing,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Hug the content: the sections stretch their children, so without the
    // Align the button would span the whole card width.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          textStyle: Theme.of(context).textTheme.bodyMedium,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A long localization plus the button's own padding can outrun a
            // narrow course column, so the label wraps instead of overflowing.
            Flexible(child: Text(label)),
            const Icon(Icons.chevron_right, size: 18.0),
            if (trailing != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8.0),
                child: trailing,
              ),
          ],
        ),
      ),
    );
  }
}
