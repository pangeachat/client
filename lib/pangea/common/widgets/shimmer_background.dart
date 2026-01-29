import 'package:flutter/material.dart';

import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';

class ShimmerBackground extends StatelessWidget {
  final Widget child;
  final Color shimmerColor;
  final Color? baseColor;
  final bool enabled;
  final BorderRadius? borderRadius;

  const ShimmerBackground({
    super.key,
    required this.child,
    this.shimmerColor = AppConfig.goldLight,
    this.baseColor,
    this.enabled = true,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    final borderRadius =
        this.borderRadius ?? BorderRadius.circular(AppConfig.borderRadius);
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: borderRadius,
              child: Shimmer.fromColors(
                baseColor: baseColor ?? shimmerColor.withValues(alpha: 0.1),
                highlightColor: shimmerColor.withValues(alpha: 0.6),
                direction: ShimmerDirection.ltr,
                child: Container(
                  decoration: BoxDecoration(
                    color: shimmerColor.withValues(alpha: 0.3),
                    borderRadius: borderRadius,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
