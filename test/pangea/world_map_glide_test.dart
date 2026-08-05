import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map_constants.dart';

void main() {
  group('glideDurationFor — scales with the zoom distance (#7239)', () {
    int ms(double a, double b) =>
        WorldMapConstants.glideDurationFor(a, b).inMilliseconds;

    test('a no-zoom move is the floor', () {
      expect(ms(5, 5), 500);
    });

    test('one zoom level adds the per-level step', () {
      expect(ms(5, 6), 700); // 500 + 1*200
    });

    test('a large move is clamped to the ceiling', () {
      expect(ms(3, 18), 2400); // 500 + 15*200 = 3500 -> clamped
    });

    test('depends only on the magnitude of the delta', () {
      expect(ms(8, 12), ms(12, 8));
    });

    // #7937 — a glide crosses every zoom level between its endpoints and each
    // is a fresh tile level to fetch, so a long sweep run too fast renders as
    // un-tiled background (the dark-mode "flashbang"). Long moves must leave
    // room for a tile round trip per level, while a single +/- step stays
    // responsive.
    test('a long sweep leaves >=150ms per zoom level crossed', () {
      // The focus button's worst case: the world floor in to focusZoom.
      const levels = WorldMapConstants.focusZoom - 3;
      expect(ms(3, WorldMapConstants.focusZoom) / levels, greaterThan(150));
    });

    test('a single +/- step stays under a second', () {
      expect(ms(5, 6), lessThan(1000));
    });
  });

  // #7937 — the scroll wheel accumulates onto the in-flight target so a fast
  // scroll adds up to one continuous move, and clamps to the camera's limits.
  group('scrollZoomTarget — eased scroll-wheel zoom (#7937)', () {
    double target(double base, double delta, {double minZoom = 3}) =>
        WorldMapConstants.scrollZoomTarget(
          base: base,
          scrollDelta: delta,
          minZoom: minZoom,
        );

    test('scrolling up (negative delta) zooms in, down zooms out', () {
      expect(target(10, -100), greaterThan(10));
      expect(target(10, 100), lessThan(10));
    });

    test('one desktop notch moves a fraction of a level, not half of one', () {
      expect(target(10, -100) - 10, closeTo(0.35, 0.001));
    });

    test('successive steps accumulate when fed the running target', () {
      final first = target(10, -100);
      final second = target(first, -100);
      expect(second - 10, closeTo(0.7, 0.001));
    });

    test('clamps to the viewport-derived floor and the shared ceiling', () {
      expect(target(3.2, 10000, minZoom: 3), 3);
      expect(target(17, -10000), WorldMapConstants.maxZoom);
    });

    test('a zero-delta scroll is a no-op', () {
      expect(target(10, 0), 10);
    });
  });

  group('glideProgress — directional pan/zoom staggering (#7239)', () {
    test(
      'endpoints: pan and zoom are 0 at t=0 and 1 at t=1, any direction',
      () {
        for (final move in [
          [3.0, 12.0], // in
          [12.0, 3.0], // out
          [7.0, 7.0], // pure pan
        ]) {
          final at0 = WorldMapConstants.glideProgress(0, move[0], move[1]);
          final at1 = WorldMapConstants.glideProgress(1, move[0], move[1]);
          expect(at0.pan, moreOrLessEquals(0));
          expect(at0.zoom, moreOrLessEquals(0));
          expect(at1.pan, moreOrLessEquals(1));
          expect(at1.zoom, moreOrLessEquals(1));
        }
      },
    );

    test(
      'zooming IN: the pan leads the zoom (pan further along mid-glide)',
      () {
        final p = WorldMapConstants.glideProgress(0.5, 3, 12);
        expect(p.pan, greaterThan(p.zoom));
      },
    );

    test('zooming OUT: the zoom leads the pan', () {
      final p = WorldMapConstants.glideProgress(0.5, 12, 3);
      expect(p.zoom, greaterThan(p.pan));
    });

    test('a pure pan (no zoom change) moves pan and zoom together', () {
      final p = WorldMapConstants.glideProgress(0.5, 7, 7);
      expect(p.pan, moreOrLessEquals(p.zoom));
    });
  });

  group('panTargetLongitude — pin-anchored pan direction (#7880)', () {
    double to(double start, double target, [double? anchor]) =>
        WorldMapConstants.panTargetLongitude(
          start: start,
          target: target,
          anchor: anchor,
        );

    test('the result is always the target modulo a full turn', () {
      for (final (s, t, a) in <(double, double, double?)>[
        (145, -81, 10),
        (175, -170, -179),
        (10, 40, 12),
        (163, 30, null),
        (-150, 170, null),
      ]) {
        expect(
          (to(s, t, a) - t) % 360,
          moreOrLessEquals(0),
          reason: 'start=$s target=$t anchor=$a',
        );
      }
    });

    test('QA reopen geometry: a wide left panel demands a >180deg westward '
        'sweep, and the anchor keeps it westward', () {
      // Camera over the Pacific (~145E), pin at ~10E visible near the LEFT
      // edge (offset -135). The activity panel covers the left half, so the
      // pin's resting spot is right-of-center: target center ~ -81 (91deg
      // WEST of the pin). Correct sweep: 226deg west, pin slides left-edge ->
      // right-of-center, on screen throughout. Shortest center-to-center
      // wraps that to +134 EAST and hurls the pin off the left edge.
      final unwrapped = to(145, -81, 10);
      expect(unwrapped, moreOrLessEquals(-81)); // west: 145 -> -81, no wrap
      expect(unwrapped - 145, moreOrLessEquals(-226)); // > 180, deliberately
    });

    test('original-video geometry: seam-straddling values take the short way '
        'toward the visible pin', () {
      // Camera at 175, pin at -179 visible +6 east across the seam, panel
      // shift puts the target center at -170. RAW linear would sweep -345
      // through 0; the anchor unwraps the target to 190 (= -170), a short
      // +15 eastward glide past the seam.
      expect(to(175, -170, -179), moreOrLessEquals(190));
    });

    test('an anchored ordinary move (no seam, no wide panel) is linear', () {
      expect(to(10, 40, 12), moreOrLessEquals(40));
      expect(to(-20, -50, -22), moreOrLessEquals(-50));
    });

    test('without an anchor, falls back to the shortest angular path', () {
      // 175 -> -179 is +6 across the seam (unwrapped 181), not -354.
      expect(to(175, -179), moreOrLessEquals(181));
      // -179 -> 175 is -6 across the seam (unwrapped -185), not +354.
      expect(to(-179, 175), moreOrLessEquals(-185));
      // Ordinary moves stay put.
      expect(to(10, 40), moreOrLessEquals(40));
    });

    test('a no-op move stays put, anchored or not', () {
      expect(to(42, 42, 42), moreOrLessEquals(42));
      expect(to(42, 42), moreOrLessEquals(42));
    });
  });
}
