import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/course_access/course_access.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The create-course preview's "Who can join?" row above Create course; it
/// opens the access sheet — course-preview.instructions.md § The page.
class CourseAccessRow extends StatelessWidget {
  final CourseAccess access;
  final VoidCallback onTap;

  /// The height the row and its gap add above the CTA, which the preview's
  /// resting height and compact threshold grow by.
  static const double heightAllowance = 72.0;

  const CourseAccessRow({super.key, required this.access, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        foregroundColor: theme.colorScheme.onSecondaryContainer,
        child: Icon(access.icon),
      ),
      title: Text(l10n.whoCanJoin),
      titleTextStyle: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      subtitle: Text(access.label(l10n)),
      subtitleTextStyle: theme.textTheme.titleMedium,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.change,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          Icon(Icons.chevron_right, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}
