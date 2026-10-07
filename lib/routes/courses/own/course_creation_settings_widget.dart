import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/course_access/course_access.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The create-course preview's settings above Create course: the "Who can
/// join?" row, which opens the access sheet, and the analytics-access switch —
/// course-preview.instructions.md § The page.
class CourseCreationSettings extends StatelessWidget {
  final CourseAccess access;
  final VoidCallback onTapAccess;
  final bool requireAnalyticsAccess;
  final ValueChanged<bool> onChangedRequireAnalyticsAccess;

  /// The height both rows and their gaps add above the CTA, which the
  /// preview's resting height and compact threshold grow by: both rows as
  /// they lay out on a phone, with the switch row's title and subtitle on two
  /// lines each.
  static const double heightAllowance = 176.0;

  const CourseCreationSettings({
    super.key,
    required this.access,
    required this.onTapAccess,
    required this.requireAnalyticsAccess,
    required this.onChangedRequireAnalyticsAccess,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
      side: BorderSide(color: theme.colorScheme.outlineVariant),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8.0,
      children: [
        ListTile(
          onTap: onTapAccess,
          visualDensity: VisualDensity.compact,
          shape: shape,
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
        ),
        // Built like the tile above rather than as a SwitchListTile, so the
        // subtitle can run under the switch instead of being squeezed beside
        // it. MergeSemantics reads it as one switch, as SwitchListTile does.
        MergeSemantics(
          child: Ink(
            decoration: ShapeDecoration(shape: shape),
            child: InkWell(
              customBorder: shape,
              onTap: () =>
                  onChangedRequireAnalyticsAccess(!requireAnalyticsAccess),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  16.0,
                  8.0,
                  24.0,
                  12.0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 16.0,
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      foregroundColor: theme.colorScheme.onSecondaryContainer,
                      child: const Icon(Symbols.bar_chart_4_bars),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            spacing: 8.0,
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.requireAnalyticsAccessTitle,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              Switch(
                                value: requireAnalyticsAccess,
                                onChanged: onChangedRequireAnalyticsAccess,
                                activeThumbColor: theme.pangea.successFixedDim,
                              ),
                            ],
                          ),
                          Text(
                            l10n.requireAnalyticsAccessSummary,
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
            ),
          ),
        ),
      ],
    );
  }
}
