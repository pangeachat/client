import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:fluffychat/config/app_config.dart';

/// A single ticker driving every [ShimmerBackground] on screen.
///
/// The pulse is a pure function of elapsed time rather than of when a
/// particular widget started animating, so shimmers stay in phase however
/// they mount, unmount, or pause — hovering one role card no longer leaves
/// it flashing against the beat of its neighbours.
///
/// The ticker only runs while something is listening.
class _ShimmerClock extends ChangeNotifier {
  _ShimmerClock._();

  static final _ShimmerClock instance = _ShimmerClock._();

  late final Ticker _ticker = Ticker((elapsed) {
    _elapsed = elapsed;
    notifyListeners();
  });

  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (!_ticker.isActive) _ticker.start();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _ticker.stop();
  }
}

class ShimmerBackground extends StatelessWidget {
  final Widget child;
  final Color? shimmerColor;
  final bool enabled;
  final BorderRadius? borderRadius;
  final Duration delayBetweenPulses;
  final double maxOpacity;

  const ShimmerBackground({
    super.key,
    required this.child,
    this.shimmerColor,
    this.enabled = true,
    this.borderRadius,
    this.delayBetweenPulses = Duration.zero,
    this.maxOpacity = 0.3,
  });

  static const Duration pulseDuration = Duration(milliseconds: 1000);

  /// Pulse strength at [elapsed], from 0 at rest to 1 at full: a pulse fades
  /// in over [pulseDuration], back out over another, then holds at rest for
  /// [delayBetweenPulses] before the next one.
  @visibleForTesting
  double pulseProgress(Duration elapsed) {
    final int pulse = pulseDuration.inMicroseconds;
    final int cycle = pulse * 2 + delayBetweenPulses.inMicroseconds;
    final int t = elapsed.inMicroseconds % cycle;

    final double linear = t < pulse
        ? t / pulse
        : t < pulse * 2
        ? 2 - t / pulse
        : 0.0;

    return Curves.easeInOut.transform(linear);
  }

  @override
  Widget build(BuildContext context) {
    // TickerMode is false for routes that aren't on screen — no reason to
    // hold the shared ticker awake for a shimmer nobody can see.
    if (!enabled || !TickerMode.valuesOf(context).enabled) {
      return child;
    }

    final theme = Theme.of(context);

    final borderRadius =
        this.borderRadius ?? BorderRadius.circular(AppConfig.borderRadius);

    final color =
        shimmerColor ??
        (theme.brightness == Brightness.light
            ? AppConfig.gold
            : AppConfig.goldLight);

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: borderRadius,
              child: ListenableBuilder(
                listenable: _ShimmerClock.instance,
                builder: (context, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha:
                          pulseProgress(_ShimmerClock.instance.elapsed) *
                          maxOpacity,
                    ),
                    borderRadius: borderRadius,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
