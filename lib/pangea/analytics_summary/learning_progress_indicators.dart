import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/analytics_misc/analytics_navigation_util.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/saved_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_summary/learning_progress_bar.dart';
import 'package:fluffychat/pangea/analytics_summary/learning_progress_indicator_button.dart';
import 'package:fluffychat/pangea/analytics_summary/progress_indicator.dart';
import 'package:fluffychat/pangea/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/pangea/learning_settings/settings_learning.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A summary of "My Analytics" shown at the top of the chat list
/// It shows a variety of progress indicators such as
/// messages sent,  words used, and error types, which can
/// be clicked to access more fine-grained analytics data.
class LearningProgressIndicators extends StatelessWidget {
  final ProgressIndicatorEnum? selected;
  final bool canSelect;

  const LearningProgressIndicators({
    super.key,
    this.selected,
    this.canSelect = true,
  });

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    if (client.userID == null) {
      return const SizedBox();
    }

    final isColumnMode = FluffyThemes.isColumnMode(context);
    final analyticsService = Matrix.of(context).analyticsDataService;

    return StreamBuilder(
      stream: MatrixState.pangeaController.userController.languageStream.stream,
      builder: (context, _) {
        final userL1 = MatrixState.pangeaController.userController.userL1;
        final userL2 = MatrixState.pangeaController.userController.userL2;

        final analyticsRoom = Matrix.of(context).client.analyticsRoomLocal();
        final updater = analyticsService.updateDispatcher;

        return StreamBuilder(
          stream: updater.constructUpdateStream.stream,
          builder: (context, _) {
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Row(
                              spacing: isColumnMode ? 16.0 : 4.0,
                              children: [
                                ...ConstructTypeEnum.values.map(
                                  (c) => HoverButton(
                                    selected: selected == c.indicator,
                                    onPressed: () {
                                      AnalyticsNavigationUtil
                                          .navigateToAnalytics(
                                        context: context,
                                        view: c.indicator,
                                      );
                                    },
                                    child: ProgressIndicatorBadge(
                                      indicator: c.indicator,
                                      loading: analyticsService.isInitializing,
                                      points: analyticsService.numConstructs(c),
                                    ),
                                  ),
                                ),
                                StreamBuilder(
                                  stream:
                                      updater.activityAnalyticsStream.stream,
                                  builder: (context, _) {
                                    final archivedActivitiesCount =
                                        analyticsRoom
                                                ?.archivedActivitiesCount ??
                                            0;
                                    return HoverButton(
                                      selected: selected ==
                                          ProgressIndicatorEnum.activities,
                                      onPressed: () {
                                        AnalyticsNavigationUtil
                                            .navigateToAnalytics(
                                          context: context,
                                          view:
                                              ProgressIndicatorEnum.activities,
                                        );
                                      },
                                      child: Tooltip(
                                        message: ProgressIndicatorEnum
                                            .activities
                                            .tooltip(context),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              size: 18,
                                              Icons.radar,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              weight: 1000,
                                            ),
                                            const SizedBox(width: 6.0),
                                            AnimatedFloatingNumber(
                                              number: archivedActivitiesCount,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          HoverButton(
                            onPressed: () => showDialog(
                              context: context,
                              builder: (c) => const SettingsLearning(),
                              barrierDismissible: false,
                            ),
                            child: Row(
                              children: [
                                if (userL1 != null && userL2 != null)
                                  Text(
                                    userL1.langCodeShort.toUpperCase(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                  ),
                                if (userL1 != null && userL2 != null)
                                  const Icon(Icons.chevron_right_outlined),
                                if (userL2 != null)
                                  Text(
                                    userL2.langCodeShort.toUpperCase(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: HoverBuilder(
                          builder: (context, hovered) {
                            return Container(
                              decoration: BoxDecoration(
                                color: (hovered && canSelect) ||
                                        (selected ==
                                            ProgressIndicatorEnum.level)
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withAlpha((0.2 * 255).round())
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(36.0),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 2.0,
                                horizontal: 4.0,
                              ),
                              child: MouseRegion(
                                cursor: canSelect
                                    ? SystemMouseCursors.click
                                    : MouseCursor.defer,
                                child: GestureDetector(
                                  onTap: canSelect
                                      ? () {
                                          AnalyticsNavigationUtil
                                              .navigateToAnalytics(
                                            context: context,
                                            view: ProgressIndicatorEnum.level,
                                          );
                                        }
                                      : null,
                                  child: FutureBuilder(
                                    future: analyticsService.derivedData,
                                    builder: (context, snapshot) {
                                      return Row(
                                        spacing: 8.0,
                                        children: [
                                          Expanded(
                                            child: LearningProgressBar(
                                              height: 24.0,
                                              loading: !snapshot.hasData,
                                              progress: snapshot
                                                      .data?.levelProgress ??
                                                  0.0,
                                            ),
                                          ),
                                          if (snapshot.hasData)
                                            Text(
                                              "⭐ ${snapshot.data!.level}",
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16.0),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
