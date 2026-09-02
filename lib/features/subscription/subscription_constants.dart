class SubscriptionConstants {
  static const String starBackground = "Background+Star+with+characters.png";

  /// How strongly the star field paints behind the subscription surfaces.
  ///
  /// Body text sits directly on this art, so the value is set by contrast
  /// rather than taste: the asset's own pixels top out at 64% alpha, and at
  /// this opacity the worst composite still clears WCAG AA (4.5:1) against
  /// `onSurface` and `onSurfaceVariant` in both themes.
  static const double starBackgroundOpacity = 0.4;
}
