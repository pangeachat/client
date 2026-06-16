import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/world/analytics_panel_controller.dart';
import 'package:fluffychat/widgets/layouts/shell_layout.dart';

/// The learning-analytics overlay docked on the right over the persistent map
/// (world_v2), opened by the top-right cluster's trackers. Driven by
/// [AnalyticsPanelController] (app-state, not the URL) so left-content
/// navigation never closes it. The summary card is pinned on the right; when a
/// vocab/grammar item is opened, its **detail** card blooms to the LEFT of the
/// summary (the summary never moves) — the RTL "personal stuff" pattern. Hosts
/// the existing analytics widgets unchanged. The close/back affordances sit
/// top-left so they never collide with the cluster pinned top-right.
class WorldAnalyticsPanel extends StatelessWidget {
  final AnalyticsPanelTab tab;

  /// The vocab/grammar construct whose detail is open, if any.
  final ConstructIdentifier? construct;

  /// Render full-bleed (Slide-Over) rather than as a docked card — the shell's
  /// [ShellLayout] decides this (narrow screens, or no room to tile).
  final bool fullBleed;

  const WorldAnalyticsPanel({
    super.key,
    required this.tab,
    this.construct,
    this.fullBleed = false,
  });

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

  void _closePanel() => AnalyticsPanelController.close();

  void _closeDetail() => AnalyticsPanelController.clearConstruct();

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

    final summaryBody = _body(
      header: _header(
        context,
        icon: Icons.close,
        tooltip: L10n.of(context).close,
        onPressed: _closePanel,
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
              onPressed: _closeDetail,
              title: construct!.lemma,
            ),
            child: _detailContent(),
          )
        : null;

    if (fullBleed) {
      // No room to tile (or narrow): one card fills the content area as a
      // Slide-Over. The detail (when open) replaces the summary; its back arrow
      // returns to the summary.
      return Material(
        color: theme.colorScheme.surface,
        child: SafeArea(child: detailBody ?? summaryBody),
      );
    }

    // Docked: cards float over the map. Summary pinned right; the detail blooms
    // to its left into the open canvas.
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summaryW =
              math.min(ShellLayout.analyticsCardMax, constraints.maxWidth);
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
