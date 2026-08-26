import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

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

  // The whole-world reset centers on the fullest viewport-sized window of the
  // given pins (#8121): at the zoom floor a portrait phone shows only a slice
  // of the world's longitudes, so a fixed (Europe) center could leave every
  // activity off-screen with nothing left to zoom.
  group('WorldMapConstants.worldResetCenter (#8121)', () {
    const phone = Size(390, 844); // height binds: ~half the longitudes visible
    const desktop = Size(1440, 900); // width binds: all longitudes visible

    /// The visible longitude span at the viewport's zoom floor.
    double lonSpanAt(Size viewport) {
      final worldPx =
          256 * math.pow(2, WorldMapConstants.minZoomFor(viewport)).toDouble();
      return math.min(360.0, viewport.width / worldPx * 360.0);
    }

    /// Wrapped absolute longitude distance in degrees.
    double lonDist(double a, double b) {
      final d = (a - b).abs() % 360;
      return d > 180 ? 360 - d : d;
    }

    test('no pins → null (caller keeps its fixed fallback)', () {
      expect(WorldMapConstants.worldResetCenter(phone, const []), isNull);
    });

    test('a phone centers on the bigger cluster when both cannot fit', () {
      // The ticket's scenario shape: an East Asia cluster (L2 Chinese) plus a
      // lone far-away pin. A phone's floor shows ~165° of longitude, so the
      // outlier must sit >165° from the cluster (measured the short way
      // around) to genuinely not co-fit; three Asian pins then outweigh one.
      final center = WorldMapConstants.worldResetCenter(phone, const [
        LatLng(10, -50), // South America — no 165° arc holds it + all of Asia
        LatLng(35, 105),
        LatLng(31, 121),
        LatLng(39, 116),
      ]);
      expect(center, isNotNull);
      // Every Asian pin sits inside the visible slice around the center.
      final half = lonSpanAt(phone) / 2;
      for (final lon in const [105.0, 121.0, 116.0]) {
        expect(lonDist(center!.longitude, lon), lessThanOrEqualTo(half));
      }
      // The outlier is (unavoidably) outside — the window took the cluster.
      expect(lonDist(center!.longitude, -50), greaterThan(half));
    });

    test('a co-fittable spread keeps every pin in view', () {
      // Europe + East Asia span ~111°, well inside a phone's ~165° slice: the
      // reset must show ALL of them, centered mid-spread, excluding none.
      final center = WorldMapConstants.worldResetCenter(phone, const [
        LatLng(10, 10),
        LatLng(35, 105),
        LatLng(31, 121),
      ]);
      expect(center, isNotNull);
      final half = lonSpanAt(phone) / 2;
      for (final lon in const [10.0, 105.0, 121.0]) {
        expect(lonDist(center!.longitude, lon), lessThanOrEqualTo(half));
      }
    });

    test('the window wraps across the antimeridian', () {
      final center = WorldMapConstants.worldResetCenter(phone, const [
        LatLng(0, 170),
        LatLng(0, -175),
        LatLng(0, 178),
      ]);
      expect(center, isNotNull);
      final half = lonSpanAt(phone) / 2;
      for (final lon in const [170.0, -175.0, 178.0]) {
        expect(lonDist(center!.longitude, lon), lessThanOrEqualTo(half));
      }
      expect(center!.longitude, inInclusiveRange(-180, 180));
    });

    test(
      'when everything fits, pins center in view rather than at an edge',
      () {
        // Desktop floor shows all longitudes; a tight cluster should sit at the
        // middle of the view, not at the window's leading edge.
        final center = WorldMapConstants.worldResetCenter(desktop, const [
          LatLng(45, 10),
          LatLng(50, 30),
        ]);
        expect(center, isNotNull);
        expect(center!.longitude, closeTo(20, 1));
      },
    );

    test('latitude picks the fuller band when height is the cut axis', () {
      // Width binds on desktop, so latitude is the constrained axis there —
      // its floor still shows ~62% of the projected world height, so the
      // outlier must sit near a pole (Mercator stretch) to genuinely not
      // co-fit with the southern pair; the two-pin cluster then wins.
      final center = WorldMapConstants.worldResetCenter(desktop, const [
        LatLng(84, 0), // near-polar outlier
        LatLng(-55, 0),
        LatLng(-60, 0),
      ]);
      expect(center, isNotNull);
      expect(center!.latitude, inInclusiveRange(-62, -50));
    });
  });
}
