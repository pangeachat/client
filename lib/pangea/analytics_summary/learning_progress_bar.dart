import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';

class LearningProgressBar extends StatelessWidget {
  final double progress;
  final double height;
  final bool loading;

  const LearningProgressBar({
    required this.progress,
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
      widthPercent: progress,
      barColor: AppConfig.goldLight,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
    );
  }
}
