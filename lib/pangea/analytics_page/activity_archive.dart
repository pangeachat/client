import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/analytics_navigation_util.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/saved_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_summary/learning_progress_indicators.dart';
import 'package:fluffychat/pangea/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../config/themes.dart';
import '../../widgets/avatar.dart';

class ActivityArchive extends StatelessWidget {
  const ActivityArchive({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final Room? analyticsRoom = Matrix.of(context).client.analyticsRoomLocal();
    final archive = analyticsRoom?.archivedActivities ?? [];
    final selectedRoomId = GoRouterState.of(context).pathParameters['roomid'];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsGeometry.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LearningProgressIndicators(
                selected: ProgressIndicatorEnum.activities,
              ),
              Expanded(
                child: MaxWidthBody(
                  withScrolling: false,
                  child: ListView.builder(
                    physics: const ClampingScrollPhysics(),
                    itemCount: archive.length + 1,
                    itemBuilder: (BuildContext context, int i) {
                      if (i == 0) {
                        return InstructionsInlineTooltip(
                          instructionsEnum: archive.isEmpty
                              ? InstructionsEnum.noSavedActivitiesYet
                              : InstructionsEnum.activityAnalyticsList,
                          padding: const EdgeInsets.all(8.0),
                        );
                      }
                      i--;
                      return AnalyticsActivityItem(
                        room: archive[i],
                        selected: archive[i].id == selectedRoomId,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnalyticsActivityItem extends StatelessWidget {
  final Room room;
  final bool selected;
  const AnalyticsActivityItem({
    super.key,
    required this.room,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final objective = room.activityPlan?.learningObjective ?? '';
    final cefrLevel = room.activityPlan?.req.cefrLevel;

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 1,
      ),
      child: Material(
        color: selected ? theme.colorScheme.secondaryContainer : null,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        clipBehavior: Clip.hardEdge,
        child: ListTile(
          visualDensity: const VisualDensity(vertical: -0.5),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: HoverBuilder(
            builder: (context, hovered) => AnimatedScale(
              duration: FluffyThemes.animationDuration,
              curve: FluffyThemes.animationCurve,
              scale: hovered ? 1.1 : 1.0,
              child: Avatar(
                borderRadius: BorderRadius.circular(4.0),
                mxContent: room.avatar,
                name: room.getLocalizedDisplayname(),
              ),
            ),
          ),
          title: Text(
            objective,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.0),
          ),
          trailing: cefrLevel != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    cefrLevel.string,
                    style: const TextStyle(fontSize: 14.0),
                  ),
                )
              : null,
          onTap: () {
            AnalyticsNavigationUtil.navigateToAnalytics(
              context: context,
              view: ProgressIndicatorEnum.activities,
              activityRoomId: room.id,
            );
          },
        ),
      ),
    );
  }
}
