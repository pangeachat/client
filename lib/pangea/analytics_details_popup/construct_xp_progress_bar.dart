import 'dart:math';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_misc/analytics_constants.dart';
import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ConstructXPProgressBar extends StatelessWidget {
  final ConstructIdentifier construct;

  const ConstructXPProgressBar({
    required this.construct,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final categories = ConstructLevelEnum.values.sorted(
      (a, b) => a.xpNeeded.compareTo(b.xpNeeded),
    );

    final analyticsService = Matrix.of(context).analyticsDataService;

    return StreamBuilder(
      stream: analyticsService.updateDispatcher.constructUpdateStream.stream,
      builder: (context, snapshot) {
        return FutureBuilder(
          future: analyticsService.getConstructUse(construct),
          builder: (context, snapshot) {
            final points = snapshot.data?.points ?? 0;
            final progress = min(1.0, points / AnalyticsConstants.xpForFlower);
            final level =
                snapshot.data?.constructLevel ?? ConstructLevelEnum.seeds;
            const iconSize = 40.0;
            return Column(
              spacing: 8.0,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    double availableGap =
                        constraints.maxWidth - (categories.length * iconSize);
                    const totalPoints = AnalyticsConstants.xpForFlower;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ...categories.map(
                          (c) {
                            final gapPercent = (c.xpNeeded / totalPoints);
                            final gap = availableGap * gapPercent;
                            availableGap -= gap;
                            return Container(
                              width: iconSize + gap,
                              alignment: Alignment.centerRight,
                              child: Opacity(
                                opacity: level == c ? 1.0 : 0.4,
                                child: c.icon(iconSize),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
                AnimatedProgressBar(
                  height: 20.0,
                  widthPercent: progress,
                  barColor: AppConfig.goldLight,
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
