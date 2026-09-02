class SubscriptionConstants {
  static const String starBackground = "Background+Star+with+characters.png";

  /// How strongly the star field paints behind the subscription surfaces.
  ///
  /// Body text sits directly on this art, so the value is set by contrast
  /// rather than taste: the asset's own pixels top out at 64% alpha, and at
  /// this opacity the worst composite still clears WCAG AA (4.5:1) against
  /// `onSurface` and `onSurfaceVariant` in both themes.
  static const double starBackgroundOpacity = 0.4;

  /// The share of a surface's height kept clear so content cannot cover the
  /// star carrying the two characters.
  ///
  /// The art is painted with `BoxFit.cover`, which on any portrait viewport
  /// scales it to the height exactly. That pins the character star to a fixed
  /// slice of the body — 74.2% to 93.3% of its height — whatever the screen
  /// size, while content height varies independently. Reserving the bottom
  /// slice is what makes the two stop competing, at every width, scroll
  /// position and text scale.
  static const double starBandFraction = 0.26;
}
