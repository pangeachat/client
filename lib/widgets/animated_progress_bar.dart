import 'dart:math';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/config/themes.dart';

class AnimatedProgressBar extends StatelessWidget {
  final double height;
  final double widthPercent;

  final Color? barColor;
  final Color? backgroundColor;
  final Duration? duration;

  const AnimatedProgressBar({
    required this.height,
    required this.widthPercent,
    this.barColor,
    this.backgroundColor,
    this.duration,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final barTotalWidth = constraints.maxWidth - 4;
        final progressWidth = min(
          barTotalWidth,
          max(18.0, widthPercent * barTotalWidth),
        );

        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                height: height,
                width: barTotalWidth,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppConfig.borderRadius),
                  ),
                  // The neutral track Material's own indicators use, so the
                  // fill is the only colour in the bar.
                  color:
                      backgroundColor ??
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: duration ?? FluffyThemes.animationDuration,
                height: height,
                width: progressWidth,
                // The default bar is the bright gold, drawn plain: it sits at
                // about 1.3:1 on the light track, and the edge that once
                // carried it was dropped by design (2026-09-14), as on the
                // course progress bar.
                decoration: BoxDecoration(
                  color: barColor ?? Theme.of(context).pangea.goldFixedDim,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppConfig.borderRadius),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
