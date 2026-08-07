import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics_data/analytics_init_error_indicator.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The blocked ("deleted") vocab list — the undo surface for
/// [AnalyticsUpdateService.blockConstructs].
///
/// Pushed under the vocab summary as `analytics:vocab/deleted`, so the panel
/// host renders a back arrow that pops to the vocab list rather than closing
/// analytics outright. Unlike that list this page has no filters, search,
/// practice button, or overflow menu — see analytics-system.instructions.md.
class BlockedVocabView extends StatelessWidget {
  final Widget closeButton;

  const BlockedVocabView({super.key, required this.closeButton});

  @override
  Widget build(BuildContext context) {
    final analyticsService = Matrix.of(context).analyticsDataService;

    return Scaffold(
      appBar: AppBar(
        leading: Center(child: closeButton),
        title: Text(
          L10n.of(context).deletedVocab,
          style: FluffyThemes.isColumnMode(context)
              ? Theme.of(context).textTheme.titleLarge
              : Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: Padding(
        padding: const EdgeInsetsGeometry.all(16.0),
        child: analyticsService.hasInitError
            ? AnalyticsInitErrorIndicator(
                reinitialize: analyticsService.reinitialize,
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
