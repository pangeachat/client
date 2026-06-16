import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';

/// Max width of a single analytics card (summary or detail) in column mode.
const double _cardMaxWidth = 488.0;

/// The learning-analytics overlay docked on the right over the persistent map
/// (world_v2), opened by the top-right cluster's trackers via `?analytics=<tab>`.
/// The summary card is pinned on the right; when a vocab/grammar item is opened
/// (`?construct=`), its **detail** card blooms to the LEFT of the summary (the
/// summary never moves) — the RTL "personal stuff" pattern. Hosts the existing
/// analytics widgets unchanged. Closing the detail drops `?construct`; closing
/// the panel drops `?analytics` (+ `?construct`). The close/back affordances sit
/// top-left so they never collide with the cluster pinned top-right.
class WorldAnalyticsPanel extends StatelessWidget {
  final AnalyticsPanelTab tab;

  /// The vocab/grammar construct whose detail is open, if any (`?construct=`).
  final ConstructIdentifier? construct;

  const WorldAnalyticsPanel({super.key, required this.tab, this.construct});

  ConstructTypeEnum? get _detailType {
    switch (tab) {
      case AnalyticsPanelTab.vocab:
        return ConstructTypeEnum.vocab;
      case AnalyticsPanelTab.grammar:
        return ConstructTypeEnum.morph;
      case AnalyticsPanelTab.sessions:
        return null;
    }
  }

  bool get _detailOpen => construct != null && _detailType != null;

  /// Drop the given query params; if none remain, fall back to the bare path.
  void _drop(BuildContext context, List<String> keys) {
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    final params = Map<String, String>.from(uri.queryParameters);
    for (final k in keys) {
      params.remove(k);
    }
    if (params.isEmpty) {
      context.go(uri.path.isEmpty ? '/' : uri.path);
      return;
    }
    context.go(uri.replace(queryParameters: params).toString());
  }

  void _closePanel(BuildContext context) =>
      _drop(context, ['analytics', 'construct']);

  void _closeDetail(BuildContext context) => _drop(context, ['construct']);

  String _summaryTitle(BuildContext context) {
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

  Widget _summaryContent() {
    switch (tab) {
      case AnalyticsPanelTab.vocab:
        return const ConstructAnalyticsView(
          view: ConstructTypeEnum.vocab,
          embedded: true,
        );
      case AnalyticsPanelTab.grammar:
        return const ConstructAnalyticsView(
          view: ConstructTypeEnum.morph,
          embedded: true,
        );
      case AnalyticsPanelTab.sessions:
        return const ActivityArchive(embedded: true);
    }
  }

  Widget _detailContent() => ConstructAnalyticsView(
    view: _detailType!,
    construct: construct,
    embedded: true,
  );

  Widget _header(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required String title,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onPressed),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body({required Widget header, required Widget child}) =>
      Column(children: [header, Expanded(child: child)]);

  Widget _roundedCard(BuildContext context, Widget body) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 4,
    borderRadius: BorderRadius.circular(AppConfig.borderRadius),
    clipBehavior: Clip.antiAlias,
    child: body,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumn = FluffyThemes.isColumnMode(context);

    final summaryBody = _body(
      header: _header(
        context,
        icon: Icons.close,
        tooltip: L10n.of(context).close,
        onPressed: () => _closePanel(context),
        title: _summaryTitle(context),
      ),
      child: _summaryContent(),
    );

    final detailBody = _detailOpen
        ? _body(
            header: _header(
              context,
              icon: Icons.arrow_back,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => _closeDetail(context),
              title: construct!.lemma,
            ),
            child: _detailContent(),
          )
        : null;

    if (!isColumn) {
      // Narrow: one card full-bleed. The detail (when open) replaces the
      // summary; its back arrow returns to the summary.
      return Material(
        color: theme.colorScheme.surface,
        child: SafeArea(child: detailBody ?? summaryBody),
      );
    }

    // Column mode: cards float over the map. Summary pinned right; the detail
    // blooms to its left into the open canvas.
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summaryW = math.min(_cardMaxWidth, constraints.maxWidth);
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (detailBody != null) ...[
                Expanded(child: _roundedCard(context, detailBody)),
                const SizedBox(width: 12),
              ],
              SizedBox(
                width: summaryW,
                child: _roundedCard(context, summaryBody),
              ),
            ],
          );
        },
      ),
    );
  }
}
