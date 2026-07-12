import 'package:flutter/animation.dart';

class WorldMapConstants {
  /// The camera zoom range — the single source for FlutterMap's MapOptions, the
  /// +/- step clamp in [zoomBy], the World reset in [resetToWorld], and the
  /// on-map control disabled states (#7171). minZoom 3 is the whole world.
  static const double minZoom = 3.0;
  static const double maxZoom = 18.0;

  /// Whether a zoom-in / zoom-out step would still change the camera, i.e. the
  /// on-map + / - button should be enabled. At a limit the matching button is
  /// disabled so it can't no-op (#7171).
  static bool canZoomIn(double zoom) => zoom < maxZoom;
  static bool canZoomOut(double zoom) => zoom > minZoom;

  /// The zoom the DELIBERATE focus button glides to for an activity (#7616) —
  /// close enough to read it as "this specific spot" (neighborhood/building
  /// level). Selection itself never zooms; only the button uses this.
  static const double focusZoom = 16.0;

  /// The zoom cap for the focus button's course fit (#7616): fitting a
  /// one-location course never dives below city level.
  static const double courseFitMaxZoom = 12.0;

  static const Duration fitSettleDelay = Duration(seconds: 2);
  static const Duration camGlideDuration = Duration(milliseconds: 600);

  // #7245 — the large tier hides while the camera's zoom is actively changing
  // and re-derives at settle.

  /// How long after the last zoom change the camera counts as settled. Short
  /// enough that cards return promptly after a pinch or scroll stops; long
  /// enough that discrete scroll-wheel ticks chain into one continuous hide.
  static const Duration zoomSettle = Duration(milliseconds: 300);

  /// The smallest camera-zoom delta treated as "zooming" — filters projection
  /// jitter during pure pans so panning never hides the large cards.
  static const double zoomChangeEpsilon = 0.01;

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
