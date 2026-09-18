import 'package:flutter/material.dart';

/// Name-derived colours (#8762). A name hashes to one of 12 hue buckets; the
/// per-bucket, per-theme values below are tuned so every coloured surface
/// clears WCAG 2.1 SC 1.4.3 (4.5:1) - the white avatar initial on its fill,
/// and name text on the app surfaces including the darkest card. Buckets that
/// already passed keep their exact pre-tuning values. Full derivation and
/// contrast report: https://github.com/pangeachat/client/issues/8762
extension StringColor on String {
  static final _colorCache = <String, Map<(double, double), Color>>{};

  /// The name's colour bucket; its hue is `colorBucket * 25.5` degrees.
  int get colorBucket {
    var sum = 0;
    for (var i = 0; i < length; i++) {
      sum += codeUnitAt(i);
    }
    return sum % 12;
  }

  // Avatar fill lightness per bucket. Alpha stays 0.75 and the initial's ink
  // stays white: retuned entries land the composited fill at luminance 0.170
  // (light theme) / 0.165 (dark), where white ink clears 4.5:1 and the disc
  // clears 3:1 against both the surface and the darkest card. 0.45 entries
  // are the buckets that already passed, byte-identical to before.
  static const _avatarLightnessLight = [
    0.370, 0.239, 0.158, 0.149, 0.162, 0.168, // buckets 0-5
    0.164, 0.158, 0.246, 0.45, 0.45, 0.403, // buckets 6-11
  ];
  static const _avatarLightnessDark = [
    0.45, 0.45, 0.345, 0.323, 0.341, 0.345, // buckets 0-5
    0.341, 0.331, 0.45, 0.45, 0.45, 0.45, // buckets 6-11
  ];

  // Name text (lightness, alpha) per bucket. Kept buckets carry exactly the
  // pre-tuning values of [color] / [lightColorText] / [darkColor]; failing
  // buckets go solid: alpha 1.0 at L 0.20 (light theme) / 0.80 (dark theme).
  static const List<(double, double)> _timelineNameLight = [
    (0.30, 0.75), (0.20, 1.0), (0.20, 1.0), (0.20, 1.0), // buckets 0-3
    (0.20, 1.0), (0.20, 1.0), (0.20, 1.0), (0.20, 1.0), // buckets 4-7
    (0.20, 1.0), (0.30, 0.75), (0.30, 0.75), (0.30, 0.75), // buckets 8-11
  ];
  // Buckets 1 and 8 pass on the dark surface but not on the real darkest
  // card (4.32:1 / 4.23:1 vs ColorScheme.fromSeed's surfaceContainerHighest),
  // so they take the solid ramp too.
  static const List<(double, double)> _timelineNameDark = [
    (0.80, 1.0), (0.80, 1.0), (0.70, 0.75), (0.70, 0.75), // buckets 0-3
    (0.70, 0.75), (0.70, 0.75), (0.70, 0.75), (0.70, 0.75), // buckets 4-7
    (0.80, 1.0), (0.80, 1.0), (0.80, 1.0), (0.80, 1.0), // buckets 8-11
  ];
  static const List<(double, double)> _profileNameLight = [
    (0.20, 0.75), (0.20, 0.75), (0.20, 1.0), (0.20, 1.0), // buckets 0-3
    (0.20, 1.0), (0.20, 1.0), (0.20, 1.0), (0.20, 1.0), // buckets 4-7
    (0.20, 0.75), (0.20, 0.75), (0.20, 0.75), (0.20, 0.75), // buckets 8-11
  ];

  Color _cached(double alpha, double lightness) {
    final byName = _colorCache[this] ??= {};
    return byName[(alpha, lightness)] ??= HSLColor.fromAHSL(
      alpha,
      colorBucket * 25.5,
      1,
      lightness,
    ).toColor();
  }

  Color get color => _cached(0.75, 0.3);

  Color get darkColor => _cached(0.75, 0.2);

  Color get lightColorText => _cached(0.75, 0.7);

  Color get lightColorAvatar => _cached(0.75, 0.45);

  /// Avatar fallback fill carrying a white initial, light theme.
  Color get avatarColorLight =>
      _cached(0.75, _avatarLightnessLight[colorBucket]);

  /// Avatar fallback fill carrying a white initial, dark theme.
  Color get avatarColorDark => _cached(0.75, _avatarLightnessDark[colorBucket]);

  /// Timeline sender-name colour for [brightness].
  Color timelineNameColor(Brightness brightness) {
    final (lightness, alpha) = brightness == Brightness.light
        ? _timelineNameLight[colorBucket]
        : _timelineNameDark[colorBucket];
    return _cached(alpha, lightness);
  }

  /// Profile display-name colour for [brightness].
  Color profileNameColor(Brightness brightness) {
    final (lightness, alpha) = brightness == Brightness.light
        ? _profileNameLight[colorBucket]
        : _timelineNameDark[colorBucket];
    return _cached(alpha, lightness);
  }
}
