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
/// create a chat, invite a member). The actions sit at the end of the title's
/// line when they fit and wrap under the title when they don't (#9492).
class CourseSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Widget> actions;

  /// The section glyph's size, shared with the shortcut's so the row's icons
  /// match.
  static const double iconSize = 20.0;

  /// Between the icon and title, and between two actions — each a full-size
  /// control since #8815, not a bare glyph that carried its own margin.
  static const double _spacing = 8.0;

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
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: _spacing,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: _spacing,
            children: [
              if (icon != null) Icon(icon, size: iconSize),
              Flexible(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: _spacing,
              children: actions,
            ),
        ],
      ),
    );
  }
}
