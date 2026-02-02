import 'package:flutter/material.dart';

/// A widget that displays a GIF overlay on top of a child widget
/// to create a loading or shimmer effect.
class StaticShimmer extends StatelessWidget {
  final Widget child;
  final double opacity;
  final Color? baseColor;
  final String gifAssetPath;
  final BorderRadius? borderRadius;

  const StaticShimmer({
    super.key,
    required this.child,
    this.opacity = 0.1,
    this.baseColor,
    this.gifAssetPath = 'static_slowed.gif',
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: ClipRRect(
            borderRadius: borderRadius ?? BorderRadius.zero,
            child: Opacity(
              opacity: opacity,
              child: ColorFiltered(
                colorFilter: baseColor != null
                    ? ColorFilter.matrix([
                        0,
                        0,
                        0,
                        0,
                        baseColor!.r,
                        0,
                        0,
                        0,
                        0,
                        baseColor!.g,
                        0,
                        0,
                        0,
                        0,
                        baseColor!.b,
                        -1,
                        -1,
                        -1,
                        1,
                        1,
                      ])
                    : const ColorFilter.mode(
                        Colors.transparent,
                        BlendMode.multiply,
                      ),
                child: Image.asset(
                  gifAssetPath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: baseColor?.withAlpha(50) ??
                          Colors.grey.withAlpha(100),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
