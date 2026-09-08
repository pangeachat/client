import 'package:flutter/material.dart';

/// A course-page section title row — sections are divided by [Divider]s (the
/// settings-page convention), each headed by this: the section's [icon], its
/// title, and the section's [actions].
///
/// The icon stands for the whole section rather than for any one control in
/// it (#8744), so it leads the row; the title beside it is what names the
/// section, leaving the icon decorative and silent to a screen reader.
///
/// The action row holds the section's "See all" ([CourseSectionButton]) and,
/// before it, any shortcut the section offers ([CourseSectionShortcut]:
/// create a chat, invite a member). The actions take the width they need and
/// the title takes the rest, so a long localized label squeezes the title
/// instead of overflowing the row.
class CourseSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Widget> actions;

  /// The section glyph's size, shared with the shortcut's so the row's icons
  /// match.
  static const double iconSize = 20.0;

  /// The share of the row the actions may take before one has to wrap —
  /// enough that no realistic label wraps in a narrow course column, and
  /// little enough that the title never disappears behind one that does.
  static const double _maxActionsFraction = 0.7;

  /// Between two actions — each a full-size control since #8815, not a bare
  /// glyph that carried its own margin.
  static const double _actionSpacing = 8.0;

  const CourseSectionHeader({
    required this.title,
    this.icon,
    this.actions = const [],
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
            if (icon != null) Icon(icon, size: iconSize),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (actions.isNotEmpty)
              // Bounding the actions is what lets a label wrap: the row hands
              // a non-flex child unbounded width, under which a wrapping
              // label can't measure itself.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * _maxActionsFraction,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: _actionSpacing,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
