import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// A level-up celebration anchored to the level badge it wraps (issue #7432).
///
/// Replaces the old top-down chat snackbar: instead of chrome dropping over
/// the conversation, the badge itself briefly pulses (scale + gold glow) and a
/// small "Level N!" chip pops out beside it, then fades away on its own. This
/// keeps the learner's eye on the analytics surface the level actually lives
/// on, per the issue's intent.
///
/// Contract (routing.instructions.md, "Single-column analytics nav bar" — no
/// stacked chrome, no timed controls):
/// - Decoration only: the chip is wrapped in [IgnorePointer], so it never
///   intercepts a tap, and it is not focusable — nothing to trap focus.
/// - Rendered by the badge's own subtree (no shell-level floating overlay);
///   the chip paints just outside the badge's bounds, so every ancestor
///   [Stack] between here and open space needs `clipBehavior: Clip.none`.
/// - The badge [child] keeps its exact layout footprint; the pulse and chip
///   are paint-time effects only.
///
/// Plain values only — the widget never reads `Matrix.of`; the Matrix-aware
/// host passes [levelUpdates] (see `AnalyticsSnapshot.levelUpdates` and the
/// world cluster), keeping this testable with a bare [StreamController].
class LevelUpBadgeCelebration extends StatefulWidget {
  /// The level badge to decorate. Rendered unchanged when idle.
  final Widget child;

  /// The level-change signal (the same `levelUpdateStream` the old snackbar
  /// listened to). Null renders [child] with no celebration wiring at all.
  final Stream<LevelUpdate>? levelUpdates;

  /// How long the chip stays fully visible before fading out. Tests shorten
  /// this.
  final Duration chipDuration;

  /// One full pulse run (a few scale/glow beats). Tests shorten this.
  final Duration pulseDuration;

  const LevelUpBadgeCelebration({
    required this.child,
    this.levelUpdates,
    this.chipDuration = defaultChipDuration,
    this.pulseDuration = defaultPulseDuration,
    super.key,
  });

  static const Duration defaultChipDuration = Duration(seconds: 4);
  static const Duration defaultPulseDuration = Duration(milliseconds: 1500);

  @override
  State<LevelUpBadgeCelebration> createState() =>
      _LevelUpBadgeCelebrationState();
}

class _LevelUpBadgeCelebrationState extends State<LevelUpBadgeCelebration>
    with TickerProviderStateMixin {
  static const double _maxScaleBoost = 0.18;
  static const int _pulseBeats = 3;

  /// Gap between the chip's trailing edge and the badge's leading edge.
  static const double _chipGap = 6.0;

  StreamSubscription<LevelUpdate>? _subscription;
  Timer? _chipTimer;

  /// The level being celebrated; null while idle (no chip in the tree).
  int? _celebratedLevel;

  late final AnimationController _pulseController;
  late final Animation<double> _scale;

  late final AnimationController _chipController;
  late final Animation<double> _chipOpacity;
  late final Animation<double> _chipScale;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: widget.pulseDuration,
      vsync: this,
    );
    // A few sine-like beats in one forward run, ending back at rest so the
    // badge is never left scaled.
    _scale = TweenSequence<double>([
      for (var i = 0; i < _pulseBeats; i++) ...[
        TweenSequenceItem(
          tween: Tween(
            begin: 1.0,
            end: 1.0 + _maxScaleBoost,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 1.0 + _maxScaleBoost,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 1,
        ),
      ],
    ]).animate(_pulseController);

    _chipController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _chipOpacity = CurvedAnimation(
      parent: _chipController,
      curve: Curves.easeOut,
    );
    _chipScale = Tween(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _chipController, curve: Curves.easeOutBack),
    );

    _subscribe();
  }

  @override
  void didUpdateWidget(LevelUpBadgeCelebration oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Broadcast StreamController streams compare equal across `.stream`
    // reads, so a host rebuild with the same source does not resubscribe.
    if (widget.levelUpdates != oldWidget.levelUpdates) _subscribe();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _chipTimer?.cancel();
    _pulseController.dispose();
    _chipController.dispose();
    super.dispose();
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = widget.levelUpdates?.listen(_onLevelUpdate);
  }

  void _onLevelUpdate(LevelUpdate update) {
    // The dispatcher only emits increases, but guard anyway: no celebration
    // unless the level actually went up.
    if (update.newLevel <= update.prevLevel || !mounted) return;

    setState(() => _celebratedLevel = update.newLevel);
    _pulseController.forward(from: 0.0);
    _chipController.forward();

    _chipTimer?.cancel();
    _chipTimer = Timer(widget.chipDuration, () {
      if (!mounted) return;
      _chipController.reverse().whenComplete(() {
        if (mounted) setState(() => _celebratedLevel = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final gold = AppConfig.goldByTheme(context);
    final celebratedLevel = _celebratedLevel;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = _scale.value;
            // Glow strength tracks the beat: full glow at the scale peak,
            // none at rest.
            final glow = ((scale - 1.0) / _maxScaleBoost).clamp(0.0, 1.0);
            return Transform.scale(
              scale: scale,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.0),
                  boxShadow: glow > 0
                      ? [
                          BoxShadow(
                            color: gold.withValues(alpha: 0.55 * glow),
                            blurRadius: 14.0 * glow,
                            spreadRadius: 3.0 * glow,
                          ),
                        ]
                      : const [],
                ),
                child: child,
              ),
            );
          },
          child: widget.child,
        ),
        if (celebratedLevel != null)
          // The chip hangs just past the badge's leading edge, vertically
          // centered on it: the OverflowBox lets it take its intrinsic width
          // without an overflow error, and the FractionalTranslation shifts
          // it fully outside so it reads as popping out of the badge.
          Positioned.fill(
            child: IgnorePointer(
              child: OverflowBox(
                // Fully unconstrained: the chip takes its intrinsic size even
                // when the badge is smaller than it (the app-bar mini badge).
                minWidth: 0.0,
                maxWidth: double.infinity,
                minHeight: 0.0,
                maxHeight: double.infinity,
                alignment: Alignment.centerLeft,
                child: FractionalTranslation(
                  translation: const Offset(-1.0, 0.0),
                  child: Padding(
                    padding: const EdgeInsets.only(right: _chipGap),
                    child: FadeTransition(
                      opacity: _chipOpacity,
                      child: ScaleTransition(
                        scale: _chipScale,
                        child: _LevelUpChip(level: celebratedLevel, gold: gold),
                      ),
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

/// The "Level N!" chip: gold pill matching the badge's palette, announced
/// once via a polite live region when it appears.
class _LevelUpChip extends StatelessWidget {
  final int level;
  final Color gold;

  const _LevelUpChip({required this.level, required this.gold});

  @override
  Widget build(BuildContext context) {
    final text = L10n.of(context).levelUpChip(level);
    return Semantics(
      liveRegion: true,
      container: true,
      label: text,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: gold,
          borderRadius: BorderRadius.circular(12.0),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4.0,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          text,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 13.0,
            height: 1.2,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
