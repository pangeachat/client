import 'dart:math';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';

class AnimatedProgressBar extends StatelessWidget {
  final double height;
  final double widthPercent;

  final Color barColor;
  final Color backgroundColor;
  final Duration? duration;

  const AnimatedProgressBar({
    required this.height,
    required this.widthPercent,
    required this.barColor,
    required this.backgroundColor,
    this.duration,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                height: height,
                width: constraints.maxWidth,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppConfig.borderRadius),
                  ),
                  color: backgroundColor,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: duration ?? FluffyThemes.animationDuration,
                height: height,
                width: widthPercent == 0
                    ? 0
                    : max(18, constraints.maxWidth * widthPercent),
                decoration: BoxDecoration(
                  color: barColor,
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
