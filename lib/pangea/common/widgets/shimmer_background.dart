import 'package:flutter/material.dart';

import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';

class ShimmerBackground extends StatelessWidget {
  final Widget child;
  final Color shimmerColor;
  final Color? baseColor;
  final bool enabled;

  const ShimmerBackground({
    super.key,
    required this.child,
    this.shimmerColor = AppConfig.goldLight,
    this.baseColor,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (enabled)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                child: Shimmer.fromColors(
                  baseColor: baseColor ?? shimmerColor.withValues(alpha: 0.1),
                  highlightColor: shimmerColor.withValues(alpha: 0.6),
                  direction: ShimmerDirection.ltr,
                  child: Container(
                    decoration: BoxDecoration(
                      color: shimmerColor.withValues(alpha: 0.3),
                      borderRadius:
                          BorderRadius.circular(AppConfig.borderRadius),
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
