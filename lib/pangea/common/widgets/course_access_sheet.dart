import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/course_access/course_access.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';

/// The "Who can join?" picker, the one place the course access settings are
/// described — joining-courses.instructions.md § Course access.
class CourseAccessSheet extends StatefulWidget {
  final CourseAccess? initialAccess;

  const CourseAccessSheet({super.key, required this.initialAccess});

  /// Resolves to the setting chosen with Done, or null when dismissed.
  static Future<CourseAccess?> show(
    BuildContext context,
    CourseAccess? initialAccess,
  ) => showAdaptiveBottomSheet<CourseAccess>(
    context: context,
    builder: (context) => CourseAccessSheet(initialAccess: initialAccess),
  );

  @override
  State<CourseAccessSheet> createState() => _CourseAccessSheetState();
}

class _CourseAccessSheetState extends State<CourseAccessSheet> {
  late CourseAccess? _selected = widget.initialAccess;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final selected = _selected;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8.0,
          children: [
            Semantics(
              header: true,
              child: Text(l10n.whoCanJoin, style: theme.textTheme.titleLarge),
            ),
            RadioGroup<CourseAccess>(
              groupValue: selected,
              onChanged: (access) => setState(() => _selected = access),
              child: Column(
                spacing: 8.0,
                children: [
                  for (final access in CourseAccess.values)
                    RadioListTile<CourseAccess>(
                      value: access,
                      controlAffinity: ListTileControlAffinity.trailing,
                      secondary: CircleAvatar(
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        foregroundColor: theme.colorScheme.onSecondaryContainer,
                        child: Icon(access.icon),
                      ),
                      title: Text(
                        access.label(l10n),
                        style: theme.textTheme.titleMedium,
                      ),
                      subtitle: Text(access.description(l10n)),
                      tileColor: access == selected
                          ? theme.colorScheme.primaryFixedDim.withAlpha(50)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius / 2,
                        ),
                        side: BorderSide(
                          width: 2.0,
                          color: access == selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              l10n.courseAccessCodeNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8.0),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.of(context).pop(selected),
              child: Text(l10n.done),
            ),
          ],
        ),
      ),
    );
  }
}
