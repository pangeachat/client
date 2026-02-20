import 'dart:math';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_misc/analytics_constants.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ConstructXPProgressBar extends StatelessWidget {
  final ConstructIdentifier construct;

  const ConstructXPProgressBar({required this.construct, super.key});

  @override
  Widget build(BuildContext context) {
    final categories = ConstructLevelEnum.values.sorted(
      (a, b) => a.xpNeeded.compareTo(b.xpNeeded),
    );

    final analyticsService = Matrix.of(context).analyticsDataService;
    final l2 =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;

    return StreamBuilder(
      stream: analyticsService.updateDispatcher.constructUpdateStream.stream,
      builder: (context, snapshot) {
        return FutureBuilder(
          future: l2 != null
              ? analyticsService.getConstructUse(construct, l2)
              : Future.value(
                  ConstructUses(
                    uses: [],
                    constructType: construct.type,
                    lemma: construct.lemma,
                    category: construct.category,
                  ),
                ),
          builder: (context, snapshot) {
            final points = snapshot.data?.points ?? 0;
            final progress = min(1.0, points / AnalyticsConstants.xpForFlower);
            final level =
                snapshot.data?.constructLevel ?? ConstructLevelEnum.seeds;
            const iconSize = 40.0;
            return Column(
              spacing: 8.0,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ...categories.map(
                      (c) => Opacity(
                        opacity: level == c ? 1.0 : 0.4,
                        child: c.icon(iconSize),
                      ),
                    ),
                  ],
                ),
                AnimatedProgressBar(
                  height: 20.0,
                  widthPercent: progress,
                  barColor: AppConfig.goldLight,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
