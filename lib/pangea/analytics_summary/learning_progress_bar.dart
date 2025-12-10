import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_summary/progress_bar/animated_progress_bar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LearningProgressBar extends StatelessWidget {
  final int level;
  final int totalXP;
  final double height;
  final bool loading;

  const LearningProgressBar({
    required this.level,
    required this.totalXP,
    required this.loading,
    required this.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        alignment: Alignment.center,
        height: height,
        child: const LinearProgressIndicator(
          color: AppConfig.goldLight,
        ),
      );
    }

    return AnimatedProgressBar(
      height: height,
      widthPercent: MatrixState.pangeaController.getAnalytics.levelProgress,
      barColor: AppConfig.goldLight,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
    );
  }
}
