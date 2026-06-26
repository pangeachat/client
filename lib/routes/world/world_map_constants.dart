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

  /// The zoom the camera glides to when an activity is focused (opened) — close
  /// enough to read it as "this specific spot" (neighborhood/building level).
  static const double focusZoom = 16.0;

  static const Duration fitSettleDelay = Duration(seconds: 2);
  static const Duration camGlideDuration = Duration(milliseconds: 600);
}
