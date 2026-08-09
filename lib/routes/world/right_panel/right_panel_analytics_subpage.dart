import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_token.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/analytics/level/level_analytics_details_content.dart';
import 'package:fluffychat/routes/world/panel_card.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';

class RightPanelAnalyticsSubpage extends StatelessWidget {
  final AnalyticsTokenParam? param;
  final IconData icon;
  final VoidCallback onLeading;
  final String tooltip;

  const RightPanelAnalyticsSubpage({
    super.key,
    required this.param,
    required this.icon,
    required this.onLeading,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final tab = param?.subpage;
    final closeButton = IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onLeading,
    );

    return PanelCard(
      child: switch (tab) {
        ProgressIndicatorEnum.morphsUsed => ConstructAnalyticsView(
          view: ConstructTypeEnum.morph,
          // The Practice FAB (→ /practice/morph). Without this the panel had
          // no way to reach practice — the entry point the world_v2 migration
          // dropped. See routing.instructions.md.
          showPracticeButton: true,
          closeButton: closeButton,
        ),
        ProgressIndicatorEnum.activities => ActivityArchive(
          closeButton: closeButton,
        ),
        ProgressIndicatorEnum.level => LevelAnalyticsDetailsContent(
          closeButton: closeButton,
        ),
        _ => ConstructAnalyticsView(
          view: ConstructTypeEnum.vocab,
          showPracticeButton: true, // the Practice FAB (→ /practice/vocab)
          closeButton: closeButton,
        ),
      },
    );
  }
}
