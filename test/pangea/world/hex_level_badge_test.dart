import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/hex_level_badge.dart';

/// Pins the paint-bounds contract behind #7801: the level badge's hexagon must
/// stay inside its own render box.
///
/// The narrow analytics bar sits the badge flush against the left edge of the
/// `Stack` that `Shimmer` wraps while analytics initialize, and `Shimmer`'s
/// mask rect is exactly the render box — so a stroke that bleeds one pixel
/// past the box is never recolored, and the hexagon's left tip stayed gold
/// while the rest of the cluster shimmered gray. The path is inset by half the
/// stroke; the round joins then reach the box edge and no further.
void main() {
  /// The sizes the badge is actually rendered at: the bar's Figma frame, the
  /// app-bar mini badge (30x26 base scaled by 0.75), and the class defaults.
  const sizes = <Size>[Size(42.0, 36.0), Size(22.5, 19.5), Size(48.0, 42.0)];

  group('hexBadgePath', () {
    for (final size in sizes) {
      test('strokes entirely inside a ${size.width}x${size.height} box', () {
        // Round joins extend half a stroke past each vertex in every
        // direction, so the painted extent is the path bounds inflated by
        // half the stroke width.
        final painted = hexBadgePath(
          size,
        ).getBounds().inflate(hexBadgeStrokeWidth / 2);

        // Tolerate float noise only; a real overflow is a full 1.25px.
        const epsilon = 0.01;
        expect(painted.left, greaterThanOrEqualTo(-epsilon));
        expect(painted.top, greaterThanOrEqualTo(-epsilon));
        expect(painted.right, lessThanOrEqualTo(size.width + epsilon));
        expect(painted.bottom, lessThanOrEqualTo(size.height + epsilon));
      });

      test('still fills the ${size.width}x${size.height} box', () {
        // The inset must not shrink the mark: the outline's outer edge should
        // land ON the box, not somewhere inside it.
        final painted = hexBadgePath(
          size,
        ).getBounds().inflate(hexBadgeStrokeWidth / 2);

        expect(painted.width, closeTo(size.width, 0.01));
        expect(painted.height, closeTo(size.height, 0.01));
      });
    }

    test(
      'keeps the hexagon silhouette — pointy sides, flat top and bottom',
      () {
        const size = Size(42.0, 36.0);
        final path = hexBadgePath(size);
        final d = hexBadgeStrokeWidth / 2;

        // Left and right vertices at mid-height, on the inset edges.
        expect(path.contains(Offset(d + 0.1, size.height / 2)), isTrue);
        expect(
          path.contains(Offset(size.width - d - 0.1, size.height / 2)),
          isTrue,
        );
        // The corners the hexagon cuts away are outside it.
        expect(path.contains(Offset(d + 0.1, d + 0.1)), isFalse);
        expect(
          path.contains(Offset(size.width - d - 0.1, size.height - d - 0.1)),
          isFalse,
        );
      },
    );
  });
}
