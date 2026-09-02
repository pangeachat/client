import 'package:flutter/material.dart';

/// A course-page section title row — sections are divided by [Divider]s (the
/// settings-page convention), each headed by this: bold title, optional
/// [trailing] action.
///
/// The trailing slot is where a section's one priority action lives (#8744):
/// its "see all" [CourseSectionButton], or — in the Participants section,
/// which offers whichever of the two is useful — the invite button. The
/// action takes the width it needs and the title takes the rest, so a long
/// localized action label squeezes the title instead of overflowing the row.
class CourseSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  /// The share of the row a trailing action may take before it has to wrap —
  /// enough that no realistic label wraps in a narrow course column, and
  /// little enough that the title never disappears behind one that does.
  static const double _maxTrailingFraction = 0.7;

  const CourseSectionHeader({required this.title, this.trailing, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          spacing: 8.0,
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (trailing != null)
              // Bounding the action is what lets it wrap: the row hands a
              // non-flex child unbounded width, under which a wrapping label
              // can't measure itself.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * _maxTrailingFraction,
                ),
                child: trailing,
              ),
          ],
        ),
      ),
    );
  }
}
