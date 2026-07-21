import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map_constants.dart';

void main() {
  // The on-map +/- buttons must grey out at the camera's zoom limits so a tap
  // can never no-op (#7171). The ceiling is the shared constant; the floor is
  // viewport-derived (#7813) and passed in by the caller.
  group('WorldMapController zoom limits (#7171)', () {
    const phone = Size(390, 844);

    test('zoom-in is enabled below max and disabled at max', () {
      expect(
        WorldMapConstants.canZoomIn(WorldMapConstants.minZoomFor(phone)),
        isTrue,
      );
      expect(
        WorldMapConstants.canZoomIn(WorldMapConstants.maxZoom - 0.5),
        isTrue,
      );
      expect(WorldMapConstants.canZoomIn(WorldMapConstants.maxZoom), isFalse);
    });

    test('zoom-out is enabled above the floor and disabled at the floor', () {
      final minZoom = WorldMapConstants.minZoomFor(phone);
      expect(
        WorldMapConstants.canZoomOut(WorldMapConstants.maxZoom, minZoom),
        isTrue,
      );
      expect(WorldMapConstants.canZoomOut(minZoom + 0.5, minZoom), isTrue);
      expect(WorldMapConstants.canZoomOut(minZoom, minZoom), isFalse);
    });
  });

  // The zoom-out floor is viewport-derived (#7813): out to where one world
  // copy (256·2^z logical px) would become smaller than the viewport's height
  // or width, whichever binds first — so a phone can pull back to (nearly) the
  // whole world instead of being pinned at the old fixed floor of 3.
  group('WorldMapConstants.minZoomFor (#7813)', () {
    double worldSideAt(double zoom) => 256 * math.pow(2, zoom).toDouble();

    test('one world copy covers the viewport at the floor, in both axes', () {
      for (final size in const [
        Size(390, 844), // phone portrait
        Size(844, 390), // phone landscape
        Size(1440, 900), // desktop
        Size(1600, 2400), // tall window — >2048px, past the old fixed floor
      ]) {
        final world = worldSideAt(WorldMapConstants.minZoomFor(size));
        expect(world, greaterThanOrEqualTo(size.height));
        expect(world, greaterThanOrEqualTo(size.width));
      }
    });

    test('height binds on a portrait phone, far below the old fixed 3', () {
      final minZoom = WorldMapConstants.minZoomFor(const Size(390, 844));
      // log2(844/256) ≈ 1.72, plus the small safety margin.
      expect(minZoom, closeTo(1.73, 0.02));
    });

    test('width binds on a wide desktop', () {
      final minZoom = WorldMapConstants.minZoomFor(const Size(1440, 900));
      // log2(1440/256) ≈ 2.49, plus the small safety margin.
      expect(minZoom, closeTo(2.50, 0.02));
    });

    test('a >2048px viewport pushes the floor above the old fixed 3', () {
      // The fixed floor froze panning here (containLatitude rejects moves once
      // the ±90 band is shorter than the viewport); the derived floor covers it.
      expect(
        WorldMapConstants.minZoomFor(const Size(1600, 2400)),
        greaterThan(3.0),
      );
    });

    test(
      'the floor sits strictly above the exact world-fits-viewport zoom',
      () {
        const size = Size(390, 844);
        final exactFit = math.log(844 / 256) / math.ln2;
        expect(WorldMapConstants.minZoomFor(size), greaterThan(exactFit));
      },
    );

    test('the range is non-empty for any plausible viewport', () {
      expect(
        WorldMapConstants.minZoomFor(const Size(3840, 2160)),
        lessThan(WorldMapConstants.maxZoom),
      );
      expect(
        WorldMapConstants.fallbackMinZoom,
        lessThan(WorldMapConstants.maxZoom),
      );
    });
  });
}
