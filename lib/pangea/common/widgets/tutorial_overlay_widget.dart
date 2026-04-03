import 'dart:collection';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/common/utils/cutout_painter.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TutorialStep {
  final GlobalKey targetKey;
  final double? borderRadius;
  final Widget? tooltip;

  final Future Function()? onTap;
  final Future Function()? onShow;

  const TutorialStep({
    required this.targetKey,
    this.borderRadius,
    this.tooltip,
    this.onTap,
    this.onShow,
  });
}

class TutorialOverlayWidget extends StatefulWidget {
  final String overlayKey;
  final List<TutorialStep> steps;

  const TutorialOverlayWidget({
    required this.overlayKey,
    required this.steps,
    super.key,
  });

  @override
  State<TutorialOverlayWidget> createState() => _TutorialOverlayWidgetState();
}

class _TutorialOverlayWidgetState extends State<TutorialOverlayWidget>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<bool> _visible = ValueNotifier<bool>(false);
  late final Queue<TutorialStep> _setQueue;

  late AnimationController _controller;
  late Animation<Rect?> _rectAnimation;

  /// The current step in the tutorial
  TutorialStep? _currentStep;

  /// The current highlighted rect for this step in the tutorial
  Rect? _currentRect;

  @override
  void initState() {
    super.initState();
    _setQueue = Queue.of(widget.steps);
    _controller = AnimationController(vsync: this, duration: _duration);
    _rectAnimation = AlwaysStoppedAnimation(null);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _visible.value = true;
      _setNextAnchor();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _visible.dispose();
    super.dispose();
  }

  Duration get _duration => FluffyThemes.animationDuration;

  double? get _tooltipLeftOffset {
    final rect = _currentRect;
    if (rect == null) return null;

    return (rect.left + (rect.width / 2) - (300.0 / 2)).clamp(
      8.0,
      MediaQuery.sizeOf(context).width - 300.0 - 8.0,
    );
  }

  Future<void> _close() async {
    _visible.value = false;
    await Future.delayed(_duration);
    if (mounted) {
      MatrixState.pAnyState.closeOverlay(widget.overlayKey);
    }
  }

  Future<void> _setNextAnchor() async {
    if (_setQueue.isEmpty) {
      await _close();
      return;
    }

    final TutorialStep newStep = _setQueue.removeFirst();
    final RenderBox? newRenderBox =
        newStep.targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (newRenderBox == null || !newRenderBox.attached) {
      await _close();
      return;
    }

    final offset = newRenderBox.localToGlobal(Offset.zero);
    final newRect = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      newRenderBox.size.width,
      newRenderBox.size.height,
    );

    _currentStep = newStep;

    if (_currentRect == null || newRect == _currentRect) {
      // First step: skip animation, jump directly to the target rect.
      _currentRect = newRect;
      _rectAnimation = AlwaysStoppedAnimation(newRect);
      if (_currentStep?.onShow != null) {
        await _currentStep?.onShow?.call();
      }
    } else {
      final tween = RectTween(begin: _currentRect, end: newRect);
      _rectAnimation = tween.animate(
        CurvedAnimation(parent: _controller, curve: Curves.fastOutSlowIn),
      );
      _currentRect = newRect;
      _controller.forward(from: 0).then((_) async {
        if (_currentStep?.onShow != null) {
          await _currentStep?.onShow?.call();
        }
      });
    }

    setState(() {});
  }

  Future<void> _onTap(TapDownDetails details) async {
    final tapPos = details.globalPosition;
    if (_currentRect == null || !_currentRect!.contains(tapPos)) return;
    if (_currentStep?.onTap != null) {
      await _currentStep?.onTap?.call();
    }
    _setNextAnchor();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _visible,
      builder: (context, visible, child) {
        return AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: _duration,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: _onTap,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _rectAnimation,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: CutoutBackgroundPainter(
                            holeRect: _rectAnimation.value,
                            borderRadius: _currentStep?.borderRadius ?? 16.0,
                          ),
                        );
                      },
                    ),
                  ),
                  if (_currentStep?.tooltip != null && _currentRect != null)
                    Positioned(
                      left: _tooltipLeftOffset,
                      top: _currentRect!.bottom + 8.0,
                      child: Material(
                        color: Colors.transparent,
                        elevation: 4,
                        child: SizedBox(
                          width: 300.0,
                          child: _currentStep!.tooltip!,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
