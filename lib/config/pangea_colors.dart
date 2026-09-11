import 'package:flutter/material.dart';

import 'package:material_color_utilities/material_color_utilities.dart';

import 'package:fluffychat/config/app_config.dart';

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
    required this.goldFixedDim,
    required this.onGoldFixed,
    required this.goldContainer,
    required this.onGoldContainer,
    required this.warning,
    required this.warningGraphic,
    required this.warningFixedDim,
    required this.onWarningFixed,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  /// Gold that reads as text: a word, an XP count, an icon beside a label.
  /// Clears 4.5:1 on the surface in both themes.
  final Color gold;

  /// Gold for a mark with a 3:1 floor: an earned star, a focus ring, a
  /// progress fill. Closer to the key colour than [gold] on light.
  final Color goldGraphic;

  /// The bright gold fill, the same value in both themes. Always pair with
  /// [onGoldFixed].
  final Color goldFixedDim;

  /// Ink on [goldFixedDim].
  final Color onGoldFixed;

  /// A tinted gold surface for washes and backfills. Always pair with
  /// [onGoldContainer].
  final Color goldContainer;

  /// Ink on [goldContainer].
  final Color onGoldContainer;

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

  static final PangeaColors _light = _fromKey(Brightness.light);
  static final PangeaColors _dark = _fromKey(Brightness.dark);

  /// The roles for [brightness], computed once per brightness.
  factory PangeaColors.of(Brightness brightness) =>
      brightness == Brightness.light ? _light : _dark;

  static PangeaColors _fromKey(Brightness brightness) {
    // AppConfig.gold and AppConfig.warning are the key colours; every role
    // below is a tone of one of them.
    final gold = TonalPalette.fromHct(Hct.fromInt(AppConfig.gold.toARGB32()));
    final warning = TonalPalette.fromHct(
      Hct.fromInt(AppConfig.warning.toARGB32()),
    );
    final light = brightness == Brightness.light;
    return PangeaColors(
      gold: Color(gold.get(light ? 40 : 80)),
      goldGraphic: Color(gold.get(light ? 50 : 80)),
      goldFixedDim: Color(gold.get(80)),
      onGoldFixed: Color(gold.get(10)),
      goldContainer: Color(gold.get(light ? 90 : 30)),
      onGoldContainer: Color(gold.get(light ? 10 : 90)),
      warning: Color(warning.get(light ? 40 : 80)),
      warningGraphic: Color(warning.get(light ? 50 : 80)),
      warningFixedDim: Color(warning.get(80)),
      onWarningFixed: Color(warning.get(10)),
      warningContainer: Color(warning.get(light ? 90 : 30)),
      onWarningContainer: Color(warning.get(light ? 10 : 90)),
    );
  }

  @override
  PangeaColors copyWith({
    Color? gold,
    Color? goldGraphic,
    Color? goldFixedDim,
    Color? onGoldFixed,
    Color? goldContainer,
    Color? onGoldContainer,
    Color? warning,
    Color? warningGraphic,
    Color? warningFixedDim,
    Color? onWarningFixed,
    Color? warningContainer,
    Color? onWarningContainer,
  }) => PangeaColors(
    gold: gold ?? this.gold,
    goldGraphic: goldGraphic ?? this.goldGraphic,
    goldFixedDim: goldFixedDim ?? this.goldFixedDim,
    onGoldFixed: onGoldFixed ?? this.onGoldFixed,
    goldContainer: goldContainer ?? this.goldContainer,
    onGoldContainer: onGoldContainer ?? this.onGoldContainer,
    warning: warning ?? this.warning,
    warningGraphic: warningGraphic ?? this.warningGraphic,
    warningFixedDim: warningFixedDim ?? this.warningFixedDim,
    onWarningFixed: onWarningFixed ?? this.onWarningFixed,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
  );

  @override
  PangeaColors lerp(PangeaColors? other, double t) {
    if (other == null) return this;
    return PangeaColors(
      gold: Color.lerp(gold, other.gold, t)!,
      goldGraphic: Color.lerp(goldGraphic, other.goldGraphic, t)!,
      goldFixedDim: Color.lerp(goldFixedDim, other.goldFixedDim, t)!,
      onGoldFixed: Color.lerp(onGoldFixed, other.onGoldFixed, t)!,
      goldContainer: Color.lerp(goldContainer, other.goldContainer, t)!,
      onGoldContainer: Color.lerp(onGoldContainer, other.onGoldContainer, t)!,
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
}
