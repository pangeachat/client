import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/home/join_course_badge.dart';

/// The reminder on the signup and login pages that a class code is waiting,
/// so moving between them never leaves the visitor wondering whether it
/// survived (signup-and-login.instructions.md § Arriving with a class code).
class ClassCodeNotice extends StatelessWidget {
  final String code;

  const ClassCodeNotice({required this.code, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          spacing: 12.0,
          children: [
            const JoinCourseBadge(size: 40.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2.0,
                children: [
                  Text(
                    l10n.courseCodeSaved(code),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    l10n.courseCodeSavedExplanation,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
