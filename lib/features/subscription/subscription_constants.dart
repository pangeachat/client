class SubscriptionConstants {
  static const String starBackground = "Background+Star+with+characters.png";

  /// How strongly the star field paints behind the subscription surfaces.
  ///
  /// Body text sits directly on this art, so the value is set by contrast
  /// rather than taste: the asset's own pixels top out at 64% alpha, and at
  /// this opacity the worst composite still clears WCAG AA (4.5:1) against
  /// `onSurface` and `onSurfaceVariant` in both themes.
  static const double starBackgroundOpacity = 0.4;

  /// Where the star carrying the two characters sits within [starBackground],
  /// as fractions of the asset's 4320x2400.
  ///
  /// The asset is really two things at once: a confetti field that wants to be
  /// ambient, and one subject that wants to be placed. These bounds are what
  /// lets the two be drawn separately — the field is cropped to stop above
  /// [starCharactersTop], and the subject is cropped out of the same file.
  static const double starCharactersLeft = 1885 / 4320;
  static const double starCharactersTop = 1780 / 2400;
  static const double starCharactersWidth = (2330 - 1885) / 4320;
  static const double starCharactersHeight = (2240 - 1780) / 2400;

  /// The asset's aspect ratio, 4320x2400.
  static const double starBackgroundAspect = 4320 / 2400;

  /// How wide the characters are drawn where they are placed as a subject.
  static const double starCharactersDisplayWidth = 180.0;
}
