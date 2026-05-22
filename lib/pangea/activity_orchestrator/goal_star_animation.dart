import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/widgets/matrix.dart';

class GoalStarAnimation extends StatefulWidget {
  final String overlayKey;
  final String startTarget;
  final String endTarget;

  const GoalStarAnimation({
    required this.overlayKey,
    required this.startTarget,
    required this.endTarget,
    super.key,
  });

  @override
  GoalStarAnimationState createState() => GoalStarAnimationState();

  static void show(
    BuildContext context, {
    required String overlayKey,
    required String startTarget,
    required String endTarget,
  }) {
    OverlayUtil.showOverlay(
      context: context,
      position: OverlayPositionEnum.centered,
      closePrevOverlay: false,
      canPop: false,
      overlayKey: overlayKey,
      child: GoalStarAnimation(
        overlayKey: overlayKey,
        startTarget: startTarget,
        endTarget: endTarget,
      ),
      ignorePointer: true,
    );
  }
}

class GoalStarAnimationState extends State<GoalStarAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  Animation<Offset>? _positionAnimation;
  Animation<double>? _arcAnimation; // vertical arc offset
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: _duration, vsync: this);

    // Single curved drive for everything
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);

    // Scale: pop in, hold, shrink out
    _scaleAnimation = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.3), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_curve);

    // Opacity: fade in fast, hold, fade out
    _opacityAnimation = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 65),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_curve);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setupAnimation();
    });
  }

  void _setupAnimation() {
    final startRenderBox = MatrixState.pAnyState.getRenderBox(
      widget.startTarget,
    );
    final endRenderBox = MatrixState.pAnyState.getRenderBox(widget.endTarget);

    if (startRenderBox == null || endRenderBox == null) {
      _close();
      return;
    }

    final startOffset = startRenderBox.localToGlobal(Offset.zero);
    final endOffset = endRenderBox.localToGlobal(Offset.zero);
    final startSize = startRenderBox.size;
    final endSize = endRenderBox.size;

    final columnWidth = FluffyThemes.isColumnMode(context)
        ? (FluffyThemes.columnWidth + FluffyThemes.navRailWidth + 2.0)
        : 0.0;

    final from = Offset(
      startOffset.dx + startSize.width / 2 - columnWidth,
      startOffset.dy + startSize.height / 2,
    );
    final to = Offset(
      endOffset.dx + endSize.width / 2 - columnWidth,
      endOffset.dy + endSize.height,
    );

    _positionAnimation = Tween<Offset>(begin: from, end: to).animate(_curve);

    // Arc: offset peaks in the middle — pulls the path into a gentle curve
    final arcHeight = ((to.dy - from.dy).abs() * 0.3).clamp(40.0, 120.0);
    _arcAnimation = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -arcHeight), weight: 50),
      TweenSequenceItem(tween: Tween(begin: -arcHeight, end: 0.0), weight: 50),
    ]).animate(_curve);

    if (mounted) setState(() => _ready = true);

    _controller.forward().then((_) => _close());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration get _duration => const Duration(milliseconds: 1800);

  void _close() {
    MatrixState.pAnyState.closeOverlay(widget.overlayKey);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.brightness == Brightness.light
        ? AppConfig.gold
        : AppConfig.goldLight;

    return IgnorePointer(
      ignoring: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              if (!_ready || _positionAnimation == null) {
                return const SizedBox();
              }

              final pos = _positionAnimation!.value;
              final arc = _arcAnimation!.value;

              return Positioned(
                left: pos.dx - 20, // center the 40px icon
                top: pos.dy + arc - 20,
                child: Opacity(
                  opacity: _opacityAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: child!,
                  ),
                ),
              );
            },
            child: Icon(Icons.star, size: 40.0, color: iconColor),
          ),
        ],
      ),
    );
  }
}
