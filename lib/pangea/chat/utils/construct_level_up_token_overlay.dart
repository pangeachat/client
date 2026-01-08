import 'dart:async';
import 'dart:math' as math;

import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

// Toggle this to switch between display modes:
// anchored: Small icon animation anchored above the word
// topCard: Card at top of screen with word and animation
enum LevelUpDisplayMode {
  anchored,
  topCard,
}

const LevelUpDisplayMode _displayMode = LevelUpDisplayMode.topCard;

class _LevelUpRequest {
  final BuildContext context;
  final ConstructIdentifier construct;
  final ConstructLevelEnum level;
  final String transformTargetId;
  final Duration duration;

  _LevelUpRequest({
    required this.context,
    required this.construct,
    required this.level,
    required this.transformTargetId,
    required this.duration,
  });

  /// Get the previous level for color transitions
  ConstructLevelEnum get previousLevel {
    switch (level) {
      case ConstructLevelEnum.greens:
        return ConstructLevelEnum.seeds;
      case ConstructLevelEnum.flowers:
        return ConstructLevelEnum.greens;
      case ConstructLevelEnum.seeds:
        return ConstructLevelEnum.seeds;
    }
  }
}

class _LevelUpQueue {
  static final List<_LevelUpRequest> _globalQueue = [];
  static bool _processing = false;

  static void add(_LevelUpRequest request) {
    _globalQueue.add(request);
    _processQueue();
  }

  static void _processQueue() {
    if (_processing) {
      return;
    }
    if (_globalQueue.isEmpty) {
      return;
    }

    _processing = true;
    final request = _globalQueue.removeAt(0);

    final bool shown = ConstructLevelUpOverlayUtil._showInternal(request);

    // If it failed to show, then we can assume the token isn't visible
    if (!shown) {
      _processing = false;
      _processQueue();
      return;
    }

    // Wait for animation to complete, then process next in queue
    Future.delayed(request.duration, () {
      _processing = false;
      _processQueue();
    });
  }

  static void clear(String transformTargetId) {
    // Remove all requests for this specific transformTargetId
    _globalQueue
        .removeWhere((req) => req.transformTargetId == transformTargetId);
  }
}

class ConstructLevelUpOverlayUtil {
  static void show(
    BuildContext context, {
    required ConstructIdentifier construct,
    required ConstructLevelEnum level,
    required String? transformTargetId,
    Duration duration = const Duration(milliseconds: 2600),
  }) {
    // Only show if we have a valid transform target
    if (transformTargetId == null || transformTargetId.isEmpty) {
      return;
    }

    final request = _LevelUpRequest(
      context: context,
      construct: construct,
      level: level,
      transformTargetId: transformTargetId,
      duration: duration,
    );
    _LevelUpQueue.add(request);
  }

  static bool _showInternal(_LevelUpRequest request) {
    switch (_displayMode) {
      case LevelUpDisplayMode.anchored:
        return _showAnchoredOverlay(request);
      case LevelUpDisplayMode.topCard:
        return _showTopCard(request);
    }
  }

  static bool _showAnchoredOverlay(_LevelUpRequest request) {
    final String overlayKey = 'construct-level-up-${request.transformTargetId}';

    final Widget card = IgnorePointer(
      ignoring: true,
      child: _AnchoredLevelUpWidget(
        construct: request.construct,
        level: request.level,
        previousLevel: request.previousLevel,
      ),
    );

    final bool shown = OverlayUtil.showOverlay(
      context: request.context,
      child: card,
      transformTargetId: request.transformTargetId,
      position: OverlayPositionEnum.transform,
      // Align follower to center but target to top center so we start above the token
      targetAnchor: Alignment.topCenter,
      followerAnchor: Alignment.center,
      backDropToDismiss: false,
      ignorePointer: true,
      overlayKey: overlayKey,
      offset: Offset.zero,
    );

    if (shown) {
      Future.delayed(request.duration, () {
        MatrixState.pAnyState.closeOverlay(overlayKey);
      });
    }

    return shown;
  }

  static bool _showTopCard(_LevelUpRequest request) {
    final String overlayKey =
        'construct-level-up-top-${request.transformTargetId}';

    final Widget card = IgnorePointer(
      ignoring: true,
      child: _TopCardLevelUpWidget(
        construct: request.construct,
        level: request.level,
        previousLevel: request.previousLevel,
      ),
    );

    final bool shown = OverlayUtil.showOverlay(
      context: request.context,
      child: card,
      position: OverlayPositionEnum.top,
      backDropToDismiss: false,
      ignorePointer: true,
      overlayKey: overlayKey,
    );

    if (shown) {
      Future.delayed(request.duration, () {
        MatrixState.pAnyState.closeOverlay(overlayKey);
      });
    }

    return shown;
  }

  static void clearQueue(String transformTargetId) {
    _LevelUpQueue.clear(transformTargetId);
  }
}

class _AnchoredLevelUpWidget extends StatefulWidget {
  final ConstructIdentifier construct;
  final ConstructLevelEnum level;
  final ConstructLevelEnum previousLevel;

  const _AnchoredLevelUpWidget({
    required this.construct,
    required this.level,
    required this.previousLevel,
  });

  @override
  State<_AnchoredLevelUpWidget> createState() => _AnchoredLevelUpWidgetState();
}

class _AnchoredLevelUpWidgetState extends State<_AnchoredLevelUpWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  late final Animation<double> _liftOpacity;
  late final Animation<double> _liftDy;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2700),
    )..forward();
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
    final Animation<double> liftPhase = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
    );
    _liftOpacity = liftPhase;
    _liftDy = Tween<double>(begin: -8.0, end: -16.0)
        .chain(CurveTween(curve: Curves.easeOut))
        .animate(liftPhase);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _liftOpacity.value,
          child: Transform.translate(
            offset: Offset(0, _liftDy.value),
            child: child,
          ),
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.transparent,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: LevelUpIconWithBurst(
          level: widget.level,
          previousLevel: widget.previousLevel,
          size: 27,
          progress: _progress,
        ),
      ),
    );
  }
}

class _TopCardLevelUpWidget extends StatefulWidget {
  final ConstructIdentifier construct;
  final ConstructLevelEnum level;
  final ConstructLevelEnum previousLevel;

  const _TopCardLevelUpWidget({
    required this.construct,
    required this.level,
    required this.previousLevel,
  });

  @override
  State<_TopCardLevelUpWidget> createState() => _TopCardLevelUpWidgetState();
}

class _TopCardLevelUpWidgetState extends State<_TopCardLevelUpWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  late final Animation<double> _cardOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2700),
    )..forward();

    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
    _cardOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 80,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 10,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getCurrentTintColor(BuildContext context) {
    final prevColor = widget.previousLevel.color(context);
    final newColor = widget.level.color(context);

    final progress = _progress.value;
    if (progress < 0.5) {
      return prevColor;
    } else if (progress < 0.67) {
      final t = (progress - 0.5) / 0.17;
      return Color.lerp(prevColor, newColor, t) ?? newColor;
    } else {
      return newColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final tintColor = _getCurrentTintColor(context);
          final backgroundColor = Color.lerp(
            theme.colorScheme.surfaceContainerHighest,
            tintColor,
            0.15,
          );

          return Opacity(
            opacity: _cardOpacity.value,
            child: Center(
              child: Container(
                margin: const EdgeInsets.only(top: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LevelUpIconWithBurst(
              level: widget.level,
              previousLevel: widget.previousLevel,
              size: 32,
              progress: _progress,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.construct.lemma,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Construct animation and burst widget, used in card and anchored modes
class LevelUpIconWithBurst extends StatefulWidget {
  final double size;
  final ConstructLevelEnum level;
  final ConstructLevelEnum previousLevel;
  final Animation<double> progress;

  const LevelUpIconWithBurst({
    super.key,
    this.size = 18,
    required this.level,
    required this.previousLevel,
    required this.progress,
  });

  @override
  State<LevelUpIconWithBurst> createState() => _LevelUpIconWithBurstState();
}

class _LevelUpIconWithBurstState extends State<LevelUpIconWithBurst> {
  late final Animation<double> _scale;
  late Widget _content;
  bool _swapped = false;
  bool _showBurst = false;

  @override
  void initState() {
    super.initState();
    _content = widget.previousLevel.icon(widget.size);

    const double minScale = 0.01;
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 50),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: minScale)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: minScale, end: 1.35)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.35, end: 1.10)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 10,
      ),
    ]).animate(widget.progress);

    //swap the content (icon) halfway through shrink/grow
    widget.progress.addListener(() {
      if (!_swapped && widget.progress.value >= 0.67) {
        setState(() {
          _content = widget.level.icon(widget.size);
          _swapped = true;
          _showBurst = true;
        });
      }
    });
  }

  /// Get the current glow color based on animation progress
  /// Color transitions from previous level color to new level color at the swap point (0.67)
  Color _getCurrentGlowColor(BuildContext context) {
    final prevColor = widget.previousLevel.color(context);
    final newColor = widget.level.color(context);
    final progress = widget.progress.value;
    if (progress < 0.5) {
      return prevColor;
    } else if (progress < 0.67) {
      // Interpolate between old and new color
      final t = (progress - 0.5) / 0.17;
      return Color.lerp(prevColor, newColor, t) ?? newColor;
    } else {
      return newColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.size * 1.8;
    return SizedBox(
      width: box,
      height: box,
      child: AnimatedBuilder(
        animation: widget.progress,
        builder: (context, _) {
          final scale = _scale.value;
          final glowColor = _getCurrentGlowColor(context);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Container(
                  width: box * 0.9,
                  height: box * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withOpacity(0.28),
                        blurRadius: 10,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showBurst)
                Center(
                  child: IgnorePointer(
                    child: _PointsBurst(
                      count: 14,
                      color: glowColor,
                      onComplete: () {
                        if (mounted) setState(() => _showBurst = false);
                      },
                    ),
                  ),
                ),
              Center(
                child: Transform.scale(
                  scale: scale,
                  child: _content,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PointsBurst extends StatefulWidget {
  final int count;
  final Color color;
  final VoidCallback? onComplete;
  const _PointsBurst({
    required this.count,
    required this.color,
    this.onComplete,
  });

  @override
  State<_PointsBurst> createState() => _PointsBurstState();
}

class _PointsBurstState extends State<_PointsBurst>
    with SingleTickerProviderStateMixin {
  static const double _particleSpeed = 50;
  static const double _gravity = 5;
  static const int _durationMs = 1400;

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _progress;
  late final List<Offset> _trajectories;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: _durationMs),
      vsync: this,
    );
    _progress = Tween<double>(begin: 0.0, end: 3.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _fade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    // Create radial trajectories - evenly distributed in a full circle
    _trajectories = List.generate(widget.count, (i) {
      final baseAngle = (i / widget.count) * 2 * math.pi;
      final angle = baseAngle + (_random.nextDouble() - 0.5) * 0.2;
      final speedMultiplier = 0.8 + _random.nextDouble() * 0.4;
      final speed = _particleSpeed * speedMultiplier * 2;
      return Offset(speed * math.cos(angle), speed * math.sin(angle));
    });

    _controller.forward().then((_) {
      if (mounted && widget.onComplete != null) widget.onComplete!();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plusWidget = Text(
      "+",
      style: BotStyle.text(
        context,
        big: true,
        setColor: false,
        existingStyle: TextStyle(color: widget.color),
      ),
    );

    return FadeTransition(
      opacity: _fade,
      child: Stack(
        children: List.generate(widget.count, (index) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final p = _progress.value;
              final traj = _trajectories[index];
              final gravityOffset = _gravity * math.pow(p, 2);
              return Transform.translate(
                offset: Offset(
                  traj.dx * p,
                  traj.dy * p + gravityOffset,
                ),
                child: plusWidget,
              );
            },
          );
        }),
      ),
    );
  }
}
