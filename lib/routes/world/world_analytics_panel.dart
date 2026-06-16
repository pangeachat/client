import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';

/// The learning-analytics view docked on the right over the persistent map
/// (world_v2), opened by the top-right cluster's trackers via `?analytics=<tab>`.
/// Hosts the existing analytics widgets unchanged; closing drops only the
/// `analytics` param (mirrors [ActivityDetailPanel]). The close affordance sits
/// top-left so it never collides with the cluster pinned top-right.
class WorldAnalyticsPanel extends StatelessWidget {
  final AnalyticsPanelTab tab;
  const WorldAnalyticsPanel({super.key, required this.tab});

  void _close(BuildContext context) {
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    final params = Map<String, String>.from(uri.queryParameters)
      ..remove('analytics');
    if (params.isEmpty) {
      context.go(uri.path.isEmpty ? '/' : uri.path);
      return;
    }
    context.go(uri.replace(queryParameters: params).toString());
  }

  String _title(BuildContext context) {
    final l10n = L10n.of(context);
    switch (tab) {
      case AnalyticsPanelTab.vocab:
        return l10n.vocab;
      case AnalyticsPanelTab.grammar:
        return l10n.grammar;
      case AnalyticsPanelTab.sessions:
        return l10n.activities;
    }
  }

  Widget _content() {
    switch (tab) {
      case AnalyticsPanelTab.vocab:
        return const ConstructAnalyticsView(view: ConstructTypeEnum.vocab);
      case AnalyticsPanelTab.grammar:
        return const ConstructAnalyticsView(view: ConstructTypeEnum.morph);
      case AnalyticsPanelTab.sessions:
        return const ActivityArchive();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumn = FluffyThemes.isColumnMode(context);

    final body = Column(
      children: [
        // Header: close (left, clear of the top-right cluster) + title.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: L10n.of(context).close,
                icon: const Icon(Icons.close),
                onPressed: () => _close(context),
              ),
              const SizedBox(width: 4),
              Text(
                _title(context),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _content()),
      ],
    );

    if (!isColumn) {
      // Narrow: full-bleed over the map.
      return Material(color: theme.colorScheme.surface, child: SafeArea(child: body));
    }

    // Column mode: an inset right-docked card (Figma).
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 4,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        clipBehavior: Clip.antiAlias,
        child: body,
      ),
    );
  }
}
