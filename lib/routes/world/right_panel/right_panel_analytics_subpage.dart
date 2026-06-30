import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_download_button.dart';
import 'package:fluffychat/routes/analytics/level/level_analytics_details_content.dart';
import 'package:fluffychat/routes/world/right_panel/panel_card_with_header.dart';

class RightPanelAnalyticsSubpage extends StatelessWidget {
  final PanelToken token;
  final IconData icon;
  final VoidCallback onLeading;
  final String tooltip;

  const RightPanelAnalyticsSubpage({
    super.key,
    required this.token,
    required this.icon,
    required this.onLeading,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    final tab = token.param;
    final title = switch (tab) {
      'grammar' => l10n.grammar,
      'sessions' => l10n.stars,
      'level' => l10n.level,
      _ => l10n.vocab,
    };

    final child = switch (tab) {
      'grammar' => ConstructAnalyticsView(
        view: ConstructTypeEnum.morph,
        // The Practice FAB (→ /practice/morph). Without this the panel had
        // no way to reach practice — the entry point the world_v2 migration
        // dropped. See routing.instructions.md.
        showPracticeButton: true,
      ),
      'sessions' => const ActivityArchive(embedded: true),
      'level' => const LevelAnalyticsDetailsContent(embedded: true),
      _ => const ConstructAnalyticsView(
        view: ConstructTypeEnum.vocab,
        showPracticeButton: true, // the Practice FAB (→ /practice/vocab)
      ),
    };

    final showDownload = kIsWeb && (tab == 'grammar' || tab == 'vocab');

    return PanelCardWithHeader(
      title: title,
      icon: icon,
      onLeading: onLeading,
      trailing: showDownload ? DownloadAnalyticsButton() : null,
      tooltip: tooltip,
      child: child,
    );
  }
}
