import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_summary/progress_bar/progress_bar.dart';
import 'package:fluffychat/pangea/analytics_summary/progress_bar/progress_bar_details.dart';

class LearningProgressBar extends StatelessWidget {
  final double? height;
  final bool loading;
  final int? totalXP;
  final double? levelProgress;

  const LearningProgressBar({
    required this.loading,
    this.height,
    this.totalXP,
    this.levelProgress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (loading || totalXP == null || levelProgress == null) {
      return Container(
        alignment: Alignment.center,
        height: height,
        child: const LinearProgressIndicator(
          color: AppConfig.goldLight,
        ),
      );
    }

    return ProgressBar(
      height: height,
      levelBars: [
        LevelBarDetails(
          fillColor: Theme.of(context).colorScheme.primary,
          currentPoints: totalXP!,
          widthMultiplier: levelProgress!,
        ),
      ],
    );
  }
}
