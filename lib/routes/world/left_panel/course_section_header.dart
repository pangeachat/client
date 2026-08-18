import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// A section header row in the Courses hub list — "Teaching · 3", "Learning ·
/// 5", "Invited · 1" — in the same divider-row style the empty state uses for
/// "Add new course" (#8425). Tapping the row collapses or expands the section;
/// the chevron turns to show which.
class CourseSectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool collapsed;
  final VoidCallback onTap;

  const CourseSectionHeader({
    super.key,
    required this.title,
    required this.count,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.labelLarge?.copyWith(color: color);

    return MergeSemantics(
      child: Semantics(
        header: true,
        expanded: !collapsed,
        label: L10n.of(context).courseSectionLabel(title, count),
        child: InkWell(
          borderRadius: BorderRadius.circular(8.0),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: ExcludeSemantics(
              child: Row(
                spacing: 8.0,
                children: [
                  Text(
                    title,
                    style: style?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  Text('$count', style: style),
                  Expanded(
                    child: Divider(color: theme.colorScheme.outlineVariant),
                  ),
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: FluffyThemes.animationDuration,
                    curve: FluffyThemes.animationCurve,
                    child: Icon(Icons.expand_more, size: 20.0, color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
