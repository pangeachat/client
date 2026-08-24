import 'dart:math' as math;

import 'package:flutter/animation.dart';

import 'package:latlong2/latlong.dart';

class WorldMapConstants {
  /// The camera zoom ceiling — the single source for FlutterMap's MapOptions,
  /// the +/- step clamp in [zoomBy], and the on-map control disabled states
  /// (#7171). The FLOOR is viewport-derived: see [minZoomFor].
  static const double maxZoom = 18.0;

  /// The zoom-out floor before the map has laid out (the camera's size is
  /// unknown until then). Safe for viewports up to ~2048px in either dimension
  /// — the pre-#7813 fixed floor.
  static const double fallbackMinZoom = 3.0;

  /// One copy of the world is `256 · 2^z` logical px wide/tall (Epsg3857,
  /// 256px tiles — flutter_map's defaults, used by our TileLayer).
  static const double _worldSideAtZoomZero = 256.0;

  /// Keeps the floor strictly above the exact world-fits-viewport zoom:
  /// containLatitude REJECTS every camera move (freezing all panning) once the
  /// ±90 band is shorter than the viewport, so we never sit on the boundary
  /// where float error could tip past it.
  static const double _minZoomMargin = 0.01;

  /// The viewport-derived zoom-out floor (#7813): zooming out stops where one
  /// world copy would become smaller than the viewport's height (binds on
  /// phones) or width (binds on wide desktops), whichever comes first. Zoom is
  /// an absolute scale, so the old fixed floor of 3 left a phone seeing <20%
  /// of the world while desktop saw most of it; deriving from the viewport
  /// lets every screen pull back to (nearly) the whole world. The height term
  /// is also exactly what keeps containLatitude from freezing panning — see
  /// [_minZoomMargin] — including on >2048px-tall windows the fixed floor
  /// didn't cover.
  static double minZoomFor(Size viewport) {
    final h = math.max(viewport.height, _worldSideAtZoomZero);
    final w = math.max(viewport.width, _worldSideAtZoomZero);
    final fitHeight = math.log(h / _worldSideAtZoomZero) / math.ln2;
    final fitWidth = math.log(w / _worldSideAtZoomZero) / math.ln2;
    return math.max(fitHeight, fitWidth) + _minZoomMargin;
  }

  /// Whether a zoom-in / zoom-out step would still change the camera, i.e. the
  /// on-map + / - button should be enabled. At a limit the matching button is
  /// disabled so it can't no-op (#7171). [minZoom] is the caller's
  /// viewport-derived floor ([minZoomFor]).
  static bool canZoomIn(double zoom) => zoom < maxZoom;
  static bool canZoomOut(double zoom, double minZoom) => zoom > minZoom;

  /// The zoom a pinch of [scale] lands on from [startZoom], clamped to the
  /// map's range ([minZoom] is the caller's viewport-derived floor, #7813). A
  /// pinch reports how far the gesture scaled the world, and one zoom level is
  /// exactly a doubling of that scale, so the level delta is the factor's
  /// base-2 logarithm. That is the same conversion flutter_map applies to a
  /// touch pinch, so a pinch moves the camera by the same amount whether the
  /// fingers are on a touchscreen or a trackpad (#8556).
  static double zoomAfterPinch(
    double startZoom,
    double scale,
    double minZoom,
  ) => (startZoom + math.log(scale) / math.ln2).clamp(minZoom, maxZoom);

  /// The zoom the DELIBERATE focus button glides to for an activity (#7616) —
  /// close enough to read it as "this specific spot" (neighborhood/building
  /// level). Selection itself never zooms; only the button uses this.
  static const double focusZoom = 16.0;

  /// The zoom cap for the focus button's course fit (#7616): fitting a
  /// one-location course never dives below city level.
  static const double courseFitMaxZoom = 12.0;

  static const Duration fitSettleDelay = Duration(seconds: 2);
  static const Duration camGlideDuration = Duration(milliseconds: 600);

  // #7245 — pin/card tiers freeze at their current size while the camera is
  // actively moving (pan, zoom, rotate, or a programmatic glide) and re-derive
  // once it settles, so a gesture never flickers a card between tiers.

  /// How long after the last camera-movement event the camera counts as
  /// settled. Short enough that tiers re-derive promptly after a pinch, pan,
  /// or scroll stops; long enough that a burst of movement events (a drag, a
  /// chain of scroll-wheel ticks) coalesces into one continuous freeze.
  static const Duration moveSettle = Duration(milliseconds: 300);

  /// Fallback cap for the L1-change pin shimmer window: it normally clears the
  /// moment a plan re-hydrates, but nothing re-hydrates when no reference-shape
  /// sessions are in view, so this bounds it. See `WorldMapController`.
  static const Duration l1WarmupMax = Duration(seconds: 4);

  // #7239 — gentler combined pan/zoom glide.

  /// A glide's length scales with how far the zoom travels: a single +/- step
  /// stays snappy (~[_camGlideMinMs]), a deep focus move glides gently
  /// (~[_camGlideMaxMs]).
  ///
  /// #7937 — the per-level rate and the ceiling are both roughly doubled. A
  /// glide crosses every zoom level between its endpoints, and each one is a
  /// fresh tile level to fetch; the old ceiling squeezed the focus button's
  /// ~13-level sweep into 1.4s (~100ms per level), far less than a tile round
  /// trip, so most of the flight rendered as un-tiled background — the
  /// "flashbang" in dark mode. The floor is deliberately unchanged so a single
  /// +/- step stays responsive: only the LONG moves (the focus button, the
  /// world reset) slow down, which is exactly where the churn was.
  static const double _camGlideMinMs = 500;
  static const double _camGlideMaxMs = 2400;
  static const double _camGlideMsPerZoom = 200;

  static Duration glideDurationFor(double startZoom, double targetZoom) {
    final ms =
        (_camGlideMinMs + (targetZoom - startZoom).abs() * _camGlideMsPerZoom)
            .clamp(_camGlideMinMs, _camGlideMaxMs);
    return Duration(milliseconds: ms.round());
  }

  /// Beyond this many zoom levels a camera move JUMPS instead of gliding
  /// (#7937). Slowing a long glide only lengthens the tile churn — a tween
  /// through N levels must fetch all N, and flutter_map can only paper over a
  /// loading level with a neighbouring one it already holds in memory. A move
  /// that also pans (the focus button, the world reset) travels into map area
  /// whose ancestors were never fetched, so there is nothing to scale up and
  /// the background shows through in tile-shaped squares. An instant move
  /// fetches exactly ONE level, which is the only way to avoid that rather
  /// than shorten it.
  ///
  /// The threshold keeps the short moves smooth: a +/- step (1 level) and an
  /// activity focus pan (0 levels) still glide, which is the motion that reads
  /// as polish. Only the big sweeps — where the glide was never legible
  /// anyway, just a blur of half-loaded tiles — snap.
  static const double instantMoveZoomDelta = 4.0;

  /// Whether a move of this size should skip the tween entirely.
  static bool movesInstantly(double startZoom, double targetZoom) =>
      (targetZoom - startZoom).abs() > instantMoveZoomDelta;

  // #7937 — the scroll wheel is deliberately NOT eased. flutter_map applies
  // each wheel event the instant it arrives, and an eased, cursor-anchored
  // version (accumulating onto the in-flight glide target over ~260ms, with a
  // reduced per-notch velocity) was built and rejected on feel: easing a
  // direct-manipulation input reads as delay and stutter, not as calm. Only the
  // PROGRAMMATIC glides above — the focus button and world reset — were slowed,
  // and those are where the tile churn actually was. If this comes up again,
  // the answer is not a shorter ease; it is leaving the wheel alone.

  /// The pan and zoom of a glide run on two overlapping intervals so the pan
  /// happens at the WIDER of the two zooms and the zoom at the narrower — keeping
  /// the on-screen sweep (and tile loading) small while still reading as one
  /// continuous move. Zooming IN: pan leads, zoom trails. Zooming OUT: reversed.
  static const Curve _camLeadCurve = Interval(
    0.0,
    0.7,
    curve: Curves.easeInOut,
  );
  static const Curve _camTrailCurve = Interval(
    0.3,
    1.0,
    curve: Curves.easeInOut,
  );

  /// Wrap an angular delta into (-180, 180] degrees.
  static double _wrapDelta(double degrees) {
    final m = degrees % 360; // Dart % is non-negative for a positive divisor.
    return m > 180 ? m - 360 : m;
  }

  /// The UNWRAPPED longitude a camera glide should tween to, so the glide's
  /// direction keeps the focused pin on screen the whole flight (#7880). The
  /// returned value is `start + delta` with delta possibly beyond +-180; the
  /// tick tweens to it linearly, and flutter_map's `move` re-normalizes each
  /// frame (its seamless-scrolling adjustment), so the sweep is continuous
  /// across the antimeridian.
  ///
  /// Choosing the direction is a choice of which world-copy of [target] to fly
  /// to, and neither naive rule is right:
  /// - RAW linear (`target - start`) sweeps the long way whenever the two
  ///   values straddle the antimeridian numerically (175 -> -179 spins -354deg
  ///   through 0) — the issue's original video.
  /// - SHORTEST center-to-center path breaks when a wide side panel pushes the
  ///   target CENTER far past the pin: pin near the left edge, panel covering
  ///   the left half, resting spot right-of-center -> the correct camera sweep
  ///   exceeds 180deg, so "shortest" flips direction and throws the pin off
  ///   screen — the QA reopen.
  ///
  /// The rule that matches the issue ("keep the spot on screen the whole
  /// time") anchors the direction to the PIN, not the center: the pin's
  /// on-screen offset must travel directly from where it is now
  /// (`wrap(anchor - start)`) to where it rests (`wrap(anchor - target)`), so
  /// the camera delta is the difference of the two — monotonic pin motion by
  /// construction, wherever the centers sit. Without an [anchor] (world reset,
  /// zoom steps, course-bounds fits) it falls back to the shortest path.
  static double panTargetLongitude({
    required double start,
    required double target,
    double? anchor,
  }) {
    if (anchor == null) return start + _wrapDelta(target - start);
    final offsetNow = _wrapDelta(anchor - start);
    final offsetDest = _wrapDelta(anchor - target);
    return start + (offsetNow - offsetDest);
  }

  /// The (pan, zoom) progress at raw glide value [t] for a move from [startZoom]
  /// to [targetZoom]. Split out so the directional staggering is unit-testable.
  static ({double pan, double zoom}) glideProgress(
    double t,
    double startZoom,
    double targetZoom,
  ) {
    if (targetZoom > startZoom) {
      // Zoom in: pan first (at the wider zoom), then zoom in.
      return (
        pan: _camLeadCurve.transform(t),
        zoom: _camTrailCurve.transform(t),
      );
    }
    if (targetZoom < startZoom) {
      // Zoom out: zoom out to the wider zoom first, then pan.
      return (
        pan: _camTrailCurve.transform(t),
        zoom: _camLeadCurve.transform(t),
      );
    }
    // Pure pan, no zoom change: one shared ease, nothing to stagger.
    final eased = Curves.easeInOut.transform(t);
    return (pan: eased, zoom: eased);
  }

  /// Where the whole-world reset points the camera (#8121). At the
  /// viewport-derived zoom floor ([minZoomFor]) one world copy fits the LARGER
  /// viewport axis, so the smaller axis shows only a slice of the world — on a
  /// portrait phone roughly half its longitudes — and a fixed center can leave
  /// every activity outside that slice. Slide a window the size of the visible
  /// slice over [points] and center on the fullest one (ties go to the tightest
  /// cluster, so the pins land mid-screen rather than at an edge), so the reset
  /// shows the maximum number of activities the floor allows. Longitude is the
  /// free axis when the floor fits the height (phones); latitude — measured in
  /// projected Mercator space, where the viewport height is a fixed fraction of
  /// the world — when it fits the width (wide desktops). Null when [points] is
  /// empty: the caller keeps its fixed fallback center.
  static LatLng? worldResetCenter(Size viewport, List<LatLng> points) {
    if (points.isEmpty) return null;
    final worldPx =
        _worldSideAtZoomZero * math.pow(2, minZoomFor(viewport)).toDouble();

    // Longitude: a circular sliding window over the visible longitude span
    // (the classic doubled-sorted-array walk, since longitudes wrap).
    final lonSpan = math.min(360.0, viewport.width / worldPx * 360.0);
    final lons = points.map((p) => p.longitude).toList()..sort();
    final n = lons.length;
    final ext = [...lons, ...lons.map((l) => l + 360)];
    final lonWin = _fullestWindow(ext, n, lonSpan);
    var centerLon = (ext[lonWin.first] + ext[lonWin.last]) / 2;
    if (centerLon > 180) centerLon -= 360;

    // Latitude picks among the points the longitude window kept — visibility
    // needs both axes, and the longitude cut is the coarser of the two.
    final lo = ext[lonWin.first], hi = ext[lonWin.last];
    bool inLonWindow(double l) =>
        (l >= lo && l <= hi) || (l + 360 >= lo && l + 360 <= hi);
    final latFrac = math.min(1.0, viewport.height / worldPx);
    final ys =
        points
            .where((p) => inLonWindow(p.longitude))
            .map((p) => _mercatorY(p.latitude))
            .toList()
          ..sort();
    final latWin = _fullestWindow(ys, ys.length, latFrac);
    final centerLat = _latFromMercatorY(
      (ys[latWin.first] + ys[latWin.last]) / 2,
    );
    return LatLng(centerLat, centerLon);
  }

  /// The (first, last) indices of the fullest [span]-wide window over the first
  /// [n] window-start candidates of sorted [values]; ties prefer the tightest
  /// spread. Two-pointer walk — [values] may be the doubled array of a circular
  /// domain, with [n] the real count so every rotation is tried exactly once.
  static ({int first, int last}) _fullestWindow(
    List<double> values,
    int n,
    double span,
  ) {
    var bestFirst = 0, bestLast = 0, bestCount = 0;
    var j = 0;
    for (var i = 0; i < n; i++) {
      if (j < i) j = i;
      while (j + 1 < i + n &&
          j + 1 < values.length &&
          values[j + 1] - values[i] <= span) {
        j++;
      }
      final count = j - i + 1;
      final spread = values[j] - values[i];
      if (count > bestCount ||
          (count == bestCount &&
              spread < values[bestLast] - values[bestFirst])) {
        bestCount = count;
        bestFirst = i;
        bestLast = j;
      }
    }
    return (first: bestFirst, last: bestLast);
  }

  /// Web-Mercator projection of a latitude to normalized world y in [0, 1]
  /// (0 = north edge), clamped to the projection's ±85.05° band — the linear
  /// space the sliding latitude window must run in, since screen pixels are
  /// linear in projected y, not in degrees.
  static double _mercatorY(double latDeg) {
    final lat = latDeg.clamp(-_maxMercatorLat, _maxMercatorLat) * math.pi / 180;
    return (1 - math.log(math.tan(math.pi / 4 + lat / 2)) / math.pi) / 2;
  }

  static double _latFromMercatorY(double y) =>
      (2 * math.atan(math.exp(math.pi * (1 - 2 * y))) - math.pi / 2) *
      180 /
      math.pi;

  static const double _maxMercatorLat = 85.05112878;
}
