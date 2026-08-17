import 'package:flutter/material.dart';

/// Where one star of a [DecorativeStars] scatter sits, in the coordinate space
/// of the [Stack] the scatter fills.
class DecorativeStarSpec {
  final double? top;
  final double? right;
  final double? bottom;
  final double? left;
  final double size;
  final double rotation;

  const DecorativeStarSpec({
    required this.size,
    this.top,
    this.right,
    this.bottom,
    this.left,
    this.rotation = 0,
  });
}

/// One large, half-opacity gold star — the texture every subscription-gated
/// surface wears, so the paywall moments read as one family with the
/// onboarding free-trial page (#7929).
class DecorativeStar extends StatelessWidget {
  /// Half opacity is the whole look: the star reads as background texture
  /// behind a shimmer skeleton, never as content competing with it.
  static const double opacity = 0.5;

  final double size;
  final double rotation;

  const DecorativeStar({super.key, required this.size, this.rotation = 0});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Transform.rotate(
        angle: rotation,
        child: Opacity(
          opacity: opacity,
          child: Text('⭐', style: TextStyle(fontSize: size)),
        ),
      ),
    );
  }
}

/// A scatter of [DecorativeStar]s over the whole of the enclosing [Stack].
///
/// Builds a [Positioned], so it must be a direct child of a [Stack]. List it
/// BEFORE whatever it decorates: the stars are texture, and must never sit
/// over text or a call to action where they would eat its contrast.
class DecorativeStars extends StatelessWidget {
  final List<DecorativeStarSpec> stars;

  const DecorativeStars({super.key, required this.stars});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            for (final star in stars)
              Positioned(
                top: star.top,
                right: star.right,
                bottom: star.bottom,
                left: star.left,
                child: DecorativeStar(size: star.size, rotation: star.rotation),
              ),
          ],
        ),
      ),
    );
  }
}
