import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/activity_suggestions/activity_suggestions_area.dart';
import 'package:fluffychat/pangea/analytics_summary/learning_progress_indicators.dart';
import 'package:fluffychat/pangea/public_spaces/public_spaces_area.dart';
import 'package:fluffychat/widgets/navigation_rail.dart';

class SuggestionsPage extends StatelessWidget {
  const SuggestionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isColumnMode && AppConfig.displayNavigationRail) ...[
              SpacesNavigationRail(
                activeSpaceId: null,
                onGoToChats: () => context.go('/rooms'),
                onGoToSpaceId: (spaceId) =>
                    context.go('/rooms?spaceId=$spaceId'),
              ),
              Container(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ],
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 16.0,
                  ),
                  child: Column(
                    spacing: 24.0,
                    children: [
                      if (!isColumnMode) const LearningProgressIndicators(),
                      const ActivitySuggestionsArea(
                        showTitle: true,
                        scrollDirection: Axis.horizontal,
                      ),
                      const PublicSpacesArea(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
