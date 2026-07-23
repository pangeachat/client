import 'dart:math' as math;

import 'package:flutter/animation.dart';

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

  // #7239 — gentler combined pan/zoom glide.

  /// A glide's length scales with how far the zoom travels: a single +/- step
  /// stays snappy (~[_camGlideMinMs]), a deep focus move glides gently
  /// (~[_camGlideMaxMs]).
  static const double _camGlideMinMs = 500;
  static const double _camGlideMaxMs = 1400;
  static const double _camGlideMsPerZoom = 110;

  static Duration glideDurationFor(double startZoom, double targetZoom) {
    final ms =
        (_camGlideMinMs + (targetZoom - startZoom).abs() * _camGlideMsPerZoom)
            .clamp(_camGlideMinMs, _camGlideMaxMs);
    return Duration(milliseconds: ms.round());
  }

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
}
