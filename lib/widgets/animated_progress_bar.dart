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
                  color:
                      backgroundColor ?? Theme.of(context).pangea.goldContainer,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: duration ?? FluffyThemes.animationDuration,
                height: height,
                width: progressWidth,
                // The default bar is the bright gold, which cannot clear 3:1 on
                // its track, so its edge is drawn in the mark gold instead; a
                // caller's own bar colour is left as given.
                decoration: BoxDecoration(
                  color: barColor ?? Theme.of(context).pangea.goldFixedDim,
                  border: barColor == null
                      ? Border.all(color: Theme.of(context).pangea.goldGraphic)
                      : null,
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
