import 'package:flutter/material.dart';

/// A course-page section title row — sections are divided by [Divider]s (the
/// settings-page convention), each headed by this: the section's [icon], its
/// title, and an optional [trailing] action.
///
/// The icon stands for the whole section rather than for any one control in
/// it (#8744), so it leads the row; the title beside it is what names the
/// section, leaving the icon decorative and silent to a screen reader.
///
/// The trailing slot holds the section's actions — its "See all"
/// [CourseSectionButton], and before it any shortcut that section offers
/// (create a chat, invite a member). The actions take the width they need and
/// the title takes the rest, so a long localized label squeezes the title
/// instead of overflowing the row.
class CourseSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;

  /// The share of the row a trailing action may take before it has to wrap —
  /// enough that no realistic label wraps in a narrow course column, and
  /// little enough that the title never disappears behind one that does.
  static const double _maxTrailingFraction = 0.7;

  const CourseSectionHeader({
    required this.title,
    this.icon,
    this.trailing,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          spacing: 8.0,
          children: [
            if (icon != null) Icon(icon, size: 20.0),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (trailing != null)
              // Bounding the actions is what lets a label wrap: the row hands
              // a non-flex child unbounded width, under which a wrapping
              // label can't measure itself.
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
