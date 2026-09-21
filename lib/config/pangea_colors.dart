import 'package:flutter/material.dart';

import 'package:material_color_utilities/material_color_utilities.dart';

/// Brand colours that must not move when the learner changes the seed.
///
/// Every role is a tone of one key colour, so its contrast against the
/// Material surfaces follows from tone distance, the same rule
/// [ColorScheme.fromSeed] applies to its own roles: a 40-tone gap clears the
/// 3:1 floor for non-text UI and a 50-tone gap clears 4.5:1 for text.
/// Callers pick the role for the job instead of a hex.
@immutable
class PangeaColors extends ThemeExtension<PangeaColors> {
  const PangeaColors({
    required this.gold,
    required this.goldGraphic,
    required this.goldFixed,
    required this.goldFixedDim,
    required this.onGoldFixed,
    required this.goldTrack,
    required this.goldContainer,
    required this.onGoldContainer,
    required this.goldHighlight,
    required this.warning,
    required this.warningGraphic,
    required this.warningFixedDim,
    required this.onWarningFixed,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.success,
    required this.successGraphic,
    required this.successFixedDim,
    required this.onSuccessFixed,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.joinable,
    required this.botFill,
    required this.onJoinable,
    required this.errorGraphic,
  });

  /// Gold that reads as text: a word, an XP count, an icon beside a label.
  /// Clears 4.5:1 on the surface in both themes.
  final Color gold;

  /// Gold for a mark with a 3:1 floor: an earned star, a focus ring, a diff
  /// underline. Closer to the key colour than [gold] on light.
  final Color goldGraphic;

  /// The pale gold, the same value in both themes, one step above
  /// [goldFixedDim] as Material's `primaryFixed` sits above `primaryFixedDim`:
  /// the XP ring's arc in dark, where the bright gold cannot clear 3:1 on the
  /// ring's own track. Always pair with [onGoldFixed].
  final Color goldFixed;

  /// The bright gold fill, the same value in both themes. Always pair with
  /// [onGoldFixed].
  final Color goldFixedDim;

  /// Ink on [goldFixedDim] and [goldFixed].
  final Color onGoldFixed;

  /// The unfilled length of a gold ring that paints over map tiles rather
  /// than a surface: dark in light so the bright arc rides on it, a mid gold
  /// in dark so it still reads over near-black cartography (#8763). Not for
  /// a bar on a surface, which takes the neutral track.
  final Color goldTrack;

  /// A tinted gold surface for washes and backfills. Always pair with
  /// [onGoldContainer].
  final Color goldContainer;

  /// Ink on [goldContainer].
  final Color onGoldContainer;

  /// The gold a level badge wears while hovered, or while the Level panel it
  /// opens is showing: [goldFixedDim] pulled a fifth of the way toward black.
  /// The badge is itself a solid gold mark, so a wash behind it would be gold
  /// on gold and a wash around it a circle the design doesn't want; the mark's
  /// own gold shifts instead (#8067). Toward black rather than down the HSL
  /// lightness axis, so the shift reads the same in both brightnesses, and no
  /// further than keeps the badge's level number, in [onGoldFixed], above
  /// 6:1 (6.41:1).
  final Color goldHighlight;

  /// Caution that reads as text: the course-language chip when the course is
  /// not in the learner's target language. Clears 4.5:1 on the surface.
  final Color warning;

  /// Caution as a mark with a 3:1 floor: the language-mismatch ring on a flag
  /// chip, a diff underline.
  final Color warningGraphic;

  /// The bright caution fill, the same value in both themes. Always pair with
  /// [onWarningFixed].
  final Color warningFixedDim;

  /// Ink on [warningFixedDim].
  final Color onWarningFixed;

  /// A tinted caution surface. Always pair with [onWarningContainer].
  final Color warningContainer;

  /// Ink on [warningContainer].
  final Color onWarningContainer;

  /// Something finished, as text or an icon read as text: a verified check,
  /// a completed label. Clears 4.5:1 on the surface.
  final Color success;

  /// Something finished, as a mark with a 3:1 floor: a diff underline for an
  /// unchanged word, a completion tick.
  final Color successGraphic;

  /// The bright completion fill, the same value in both themes. Always pair
  /// with [onSuccessFixed].
  final Color successFixedDim;

  /// Ink on [successFixedDim].
  final Color onSuccessFixed;

  /// A tinted completion surface. Always pair with [onSuccessContainer].
  final Color successContainer;

  /// Ink on [successContainer].
  final Color onSuccessContainer;

  /// The joinable-session green: the world map's "you can join this" pin
  /// and the badges that echo it. The same value in both themes, at the
  /// brightest tone of its ramp that still carries white text at 4.5:1.
  final Color joinable;

  /// The bot's body fill. The same purple in both themes and whatever seed the
  /// learner picks, because the bot is a character rather than part of the UI:
  /// the same face appears in places the app cannot recolour, and a bot that
  /// changed colour with the theme read as another piece of chrome. The one
  /// role that is its key rather than a tone of it, so a graphic on a surface
  /// at 4.4:1 in light and far clear of the 3:1 floor on the dark surfaces.
  final Color botFill;

  /// Ink on [joinable].
  final Color onJoinable;

  /// An error as a mark with a 3:1 floor: the composer's correction
  /// underline and highlight, a ring segment, a wrong-answer tint. A tone of
  /// Material's own error palette, so it is the same red as
  /// `colorScheme.error`; but the scheme's dark `error` is a T80 pastel that
  /// reads as pink on an underline, so this is the most chromatic tone that
  /// still clears 3:1 on the darkest card: T50 in light, T60 in dark. Text
  /// and the icon beside it keep `colorScheme.error`.
  final Color errorGraphic;

  static final PangeaColors _light = _fromKey(Brightness.light);
  static final PangeaColors _dark = _fromKey(Brightness.dark);

  /// The roles for [brightness], computed once per brightness.
  factory PangeaColors.of(Brightness brightness) =>
      brightness == Brightness.light ? _light : _dark;

  /// T49 is the brightest tone of the joinable ramp that clears 4.5:1 under
  /// white ink; T50 measures 4.47:1.
  static const int _joinableTone = 49;

  /// The brand gold, the key colour the gold family is tones of. Read
  /// nowhere else; widgets take a gold role from the theme.
  static const Color goldKey = Color(0xFFFDBF01);

  /// The success green, the key colour the success family is tones of. Read
  /// nowhere else; widgets take a success role from the theme.
  static const Color successKey = Color(0xFF33D057);

  /// The caution orange, the key colour the warning family is tones of.
  /// Orange rather than the org doc's red, which lands on Material's error
  /// tones. Read nowhere else.
  static const Color warningKey = Color(0xFFD27C0C);

  /// The joinable-session green, the key colour [joinable] is a tone of. Read
  /// nowhere else; the world map reaches the state colour through
  /// ActivityPinState.bodyColor.
  static const Color joinableKey = Color(0xFF34A853);

  /// The brand purple, the bot's body colour and the default scheme seed.
  /// Read nowhere else; widgets take [botFill] from the theme.
  static const Color brandKey = Color(0xFF8560E0);

  static PangeaColors _fromKey(Brightness brightness) {
    // The keys above are the key colours; every role below is a tone of one
    // of them.
    final gold = TonalPalette.fromHct(Hct.fromInt(goldKey.toARGB32()));
    final warning = TonalPalette.fromHct(Hct.fromInt(warningKey.toARGB32()));
    final success = TonalPalette.fromHct(Hct.fromInt(successKey.toARGB32()));
    final joinable = TonalPalette.fromHct(Hct.fromInt(joinableKey.toARGB32()));
    // Material's error palette (DynamicScheme.errorPalette): hue 25, chroma
    // 84, the one every ColorScheme.fromSeed shares whatever the seed.
    final error = TonalPalette.of(25.0, 84.0);
    final light = brightness == Brightness.light;
    return PangeaColors(
      gold: Color(gold.get(light ? 40 : 80)),
      goldGraphic: Color(gold.get(light ? 50 : 80)),
      goldFixed: Color(gold.get(90)),
      goldFixedDim: Color(gold.get(80)),
      onGoldFixed: Color(gold.get(10)),
      goldTrack: Color(gold.get(light ? 20 : 50)),
      goldContainer: Color(gold.get(light ? 90 : 30)),
      onGoldContainer: Color(gold.get(light ? 10 : 90)),
      goldHighlight: Color.lerp(Color(gold.get(80)), Colors.black, 0.2)!,
      warning: Color(warning.get(light ? 40 : 80)),
      warningGraphic: Color(warning.get(light ? 50 : 80)),
      warningFixedDim: Color(warning.get(80)),
      onWarningFixed: Color(warning.get(10)),
      warningContainer: Color(warning.get(light ? 90 : 30)),
      onWarningContainer: Color(warning.get(light ? 10 : 90)),
      success: Color(success.get(light ? 40 : 80)),
      successGraphic: Color(success.get(light ? 50 : 80)),
      successFixedDim: Color(success.get(80)),
      onSuccessFixed: Color(success.get(10)),
      successContainer: Color(success.get(light ? 90 : 30)),
      onSuccessContainer: Color(success.get(light ? 10 : 90)),
      joinable: Color(joinable.get(_joinableTone)),
      botFill: brandKey,
      onJoinable: Color(joinable.get(100)),
      errorGraphic: Color(error.get(light ? 50 : 60)),
    );
  }

  @override
  PangeaColors copyWith({
    Color? gold,
    Color? goldGraphic,
    Color? goldFixed,
    Color? goldFixedDim,
    Color? onGoldFixed,
    Color? goldTrack,
    Color? goldContainer,
    Color? onGoldContainer,
    Color? goldHighlight,
    Color? warning,
    Color? warningGraphic,
    Color? warningFixedDim,
    Color? onWarningFixed,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? success,
    Color? successGraphic,
    Color? successFixedDim,
    Color? onSuccessFixed,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? joinable,
    Color? botFill,
    Color? onJoinable,
    Color? errorGraphic,
  }) => PangeaColors(
    gold: gold ?? this.gold,
    goldGraphic: goldGraphic ?? this.goldGraphic,
    goldFixed: goldFixed ?? this.goldFixed,
    goldFixedDim: goldFixedDim ?? this.goldFixedDim,
    onGoldFixed: onGoldFixed ?? this.onGoldFixed,
    goldTrack: goldTrack ?? this.goldTrack,
    goldContainer: goldContainer ?? this.goldContainer,
    onGoldContainer: onGoldContainer ?? this.onGoldContainer,
    goldHighlight: goldHighlight ?? this.goldHighlight,
    warning: warning ?? this.warning,
    warningGraphic: warningGraphic ?? this.warningGraphic,
    warningFixedDim: warningFixedDim ?? this.warningFixedDim,
    onWarningFixed: onWarningFixed ?? this.onWarningFixed,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    success: success ?? this.success,
    successGraphic: successGraphic ?? this.successGraphic,
    successFixedDim: successFixedDim ?? this.successFixedDim,
    onSuccessFixed: onSuccessFixed ?? this.onSuccessFixed,
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    joinable: joinable ?? this.joinable,
    botFill: botFill ?? this.botFill,
    onJoinable: onJoinable ?? this.onJoinable,
    errorGraphic: errorGraphic ?? this.errorGraphic,
  );

  @override
  PangeaColors lerp(PangeaColors? other, double t) {
    if (other == null) return this;
    return PangeaColors(
      gold: Color.lerp(gold, other.gold, t)!,
      goldGraphic: Color.lerp(goldGraphic, other.goldGraphic, t)!,
      goldFixed: Color.lerp(goldFixed, other.goldFixed, t)!,
      goldFixedDim: Color.lerp(goldFixedDim, other.goldFixedDim, t)!,
      onGoldFixed: Color.lerp(onGoldFixed, other.onGoldFixed, t)!,
      goldTrack: Color.lerp(goldTrack, other.goldTrack, t)!,
      goldContainer: Color.lerp(goldContainer, other.goldContainer, t)!,
      onGoldContainer: Color.lerp(onGoldContainer, other.onGoldContainer, t)!,
      goldHighlight: Color.lerp(goldHighlight, other.goldHighlight, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningGraphic: Color.lerp(warningGraphic, other.warningGraphic, t)!,
      warningFixedDim: Color.lerp(warningFixedDim, other.warningFixedDim, t)!,
      onWarningFixed: Color.lerp(onWarningFixed, other.onWarningFixed, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      successGraphic: Color.lerp(successGraphic, other.successGraphic, t)!,
      successFixedDim: Color.lerp(successFixedDim, other.successFixedDim, t)!,
      onSuccessFixed: Color.lerp(onSuccessFixed, other.onSuccessFixed, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      joinable: Color.lerp(joinable, other.joinable, t)!,
      botFill: Color.lerp(botFill, other.botFill, t)!,
      onJoinable: Color.lerp(onJoinable, other.onJoinable, t)!,
      errorGraphic: Color.lerp(errorGraphic, other.errorGraphic, t)!,
    );
  }
}

extension PangeaColorsTheme on ThemeData {
  /// The brand roles for this theme. Falls back to the roles for the theme's
  /// brightness when the extension was not registered, so a bare
  /// [ThemeData] in a test still resolves gold.
  PangeaColors get pangea =>
      extension<PangeaColors>() ?? PangeaColors.of(brightness);

  /// The theme's light tone: the surface in light, its ink in dark. The ink
  /// for a fill that has been darkened toward black, such as a pressed
  /// button, where the fill's own on-colour no longer reads.
  Color get lightTone => brightness == Brightness.light
      ? colorScheme.surface
      : colorScheme.onSurface;

  /// How dark the scrim paints over the screen an overlay covers — the
  /// message toolbar's backdrop and the tutorial's spotlight layer, the two
  /// surfaces that darken the whole app rather than a widget.
  ///
  /// Lighter in dark than in light, because a different thing limits each.
  /// In light the scrim is the background the round [toolbarButtonFill]
  /// buttons sit on, and past 0.6 that pale fill drops under the 3:1
  /// non-text floor. In dark the surface under the scrim is already near
  /// black, so those buttons hold about 6.2:1 whatever the alpha, and all
  /// the alpha decides is how much of the chat survives: at 0.8 almost none
  /// of it did and the panel read as a solid black rectangle.
  double get scrimOpacity => brightness == Brightness.light ? 0.6 : 0.45;

  /// The fill of a round toolbar button, which floats over the scrim in
  /// both themes. It has to stand off that scrim and not be the own-message
  /// bubble's colour: in light the bubble is `primary`, so the button takes
  /// the pale `primaryFixedDim` (3.5:1 on the scrim, where `primaryContainer`
  /// is under 2:1); in dark the bubble is that pale lavender, so the button
  /// keeps `primaryContainer` (6.2:1, since the dark scrim is near black).
  Color get toolbarButtonFill => brightness == Brightness.light
      ? colorScheme.primaryFixedDim
      : colorScheme.primaryContainer;

  /// Ink on [toolbarButtonFill].
  Color get onToolbarButtonFill => brightness == Brightness.light
      ? colorScheme.onPrimaryFixedVariant
      : colorScheme.onPrimaryContainer;
}
