import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';

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
    // A shimmer whose run just ended removed itself during that notification,
    // and hasListeners doesn't drop until notifyListeners returns.
    if (!hasListeners) _ticker.stop();
  });

  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (!_ticker.isActive) {
      // A restarted ticker counts from zero; a run must not start from the
      // last run's time.
      _elapsed = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _ticker.stop();
  }
}

/// Pulses a wash over [child] to draw the eye to it.
///
/// Each time the shimmer turns on — it mounts, [enabled] flips on, or its
/// route comes back on screen — it pulses [pulsesPerRun] times and stops.
/// Motion that starts on its own and lasts more than five seconds needs a
/// pause control under WCAG 2.2.2 (#9003); a run this short needs none.
class ShimmerBackground extends StatefulWidget {
  final Widget child;
  final Color? shimmerColor;
  final bool enabled;
  final BorderRadius? borderRadius;

  /// Rest after each pulse. It counts toward the run, so keep [runDuration]
  /// under five seconds.
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

  static const int pulsesPerRun = 2;

  Duration get _cycle => pulseDuration * 2 + delayBetweenPulses;

  @visibleForTesting
  Duration get runDuration => _cycle * pulsesPerRun;

  /// Pulse strength at [elapsed], from 0 at rest to 1 at full: a pulse fades
  /// in over [pulseDuration], back out over another, then holds at rest for
  /// [delayBetweenPulses] before the next one.
  @visibleForTesting
  double pulseProgress(Duration elapsed) {
    final int pulse = pulseDuration.inMicroseconds;
    final int cycle = _cycle.inMicroseconds;
    final int t = elapsed.inMicroseconds % cycle;

    final double linear = t < pulse
        ? t / pulse
        : t < pulse * 2
        ? 2 - t / pulse
        : 0.0;

    return Curves.easeInOut.transform(linear);
  }

  @override
  State<ShimmerBackground> createState() => _ShimmerBackgroundState();
}

class _ShimmerBackgroundState extends State<ShimmerBackground> {
  static _ShimmerClock get _clock => _ShimmerClock.instance;

  /// Clock time the current run started at; null when no run is going.
  Duration? _runStart;

  /// The run ended while the shimmer stayed on. Cleared when it turns off, so
  /// turning it back on starts a new run.
  bool _runDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRun();
  }

  @override
  void didUpdateWidget(ShimmerBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRun();
  }

  @override
  void dispose() {
    _endRun();
    super.dispose();
  }

  void _syncRun() {
    // TickerMode is false for routes that aren't on screen — no reason to
    // hold the shared ticker awake for a shimmer nobody can see.
    if (!widget.enabled || !TickerMode.valuesOf(context).enabled) {
      _endRun();
      _runDone = false;
      return;
    }
    if (_runStart != null || _runDone) return;

    _clock.addListener(_onTick);
    // Start at the top of the pulse the clock is in, so a shimmer that turns
    // on beside running ones joins them in phase, and that pulse counts.
    final int cycle = widget._cycle.inMicroseconds;
    _runStart = Duration(
      microseconds: _clock.elapsed.inMicroseconds ~/ cycle * cycle,
    );
  }

  void _onTick() => setState(() {
    if (_clock.elapsed - _runStart! >= widget.runDuration) {
      _endRun();
      _runDone = true;
    }
  });

  void _endRun() {
    if (_runStart == null) return;
    _clock.removeListener(_onTick);
    _runStart = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_runStart == null && !_runDone) return widget.child;

    final theme = Theme.of(context);

    final borderRadius =
        widget.borderRadius ?? BorderRadius.circular(AppConfig.borderRadius);

    final color = widget.shimmerColor ?? theme.pangea.goldFixedDim;

    // The Stack stays after the run ends, so the child isn't remounted.
    return Stack(
      children: [
        widget.child,
        if (_runStart != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: borderRadius,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha:
                          widget.pulseProgress(_clock.elapsed) *
                          widget.maxOpacity,
                    ),
                    borderRadius: borderRadius,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
