import 'package:flutter/material.dart';

/// How a locked map pin or large card is drawn: solid gray, washed toward the
/// theme's muted outline tone so it recedes without going see-through
/// (#9333 prototype).
class LockedPinStyle extends StatelessWidget {
  final bool locked;
  final Widget child;

  const LockedPinStyle({super.key, required this.locked, required this.child});

  /// How much of the pin's own (desaturated) shading survives; the rest is
  /// the flat muted tone.
  static const double _shadeWeight = 0.45;

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    final muted = Theme.of(context).colorScheme.outlineVariant;
    const w = _shadeWeight;
    final r = (1 - w) * muted.r * 255;
    final g = (1 - w) * muted.g * 255;
    final b = (1 - w) * muted.b * 255;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix([
        w * 0.2126, w * 0.7152, w * 0.0722, 0, r, //
        w * 0.2126, w * 0.7152, w * 0.0722, 0, g, //
        w * 0.2126, w * 0.7152, w * 0.0722, 0, b, //
        0, 0, 0, 1, 0, //
      ]),
      child: child,
    );
  }
}
