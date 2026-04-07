import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/common/utils/cutout_painter.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay_orchestrator.dart';

class TutorialStep {
  final GlobalKey targetKey;
  final double? borderRadius;
  final Widget? tooltip;
  final Size? tooltipSize;

  final Future<void> Function()? onTap;

  const TutorialStep({
    required this.targetKey,
    this.borderRadius,
    this.tooltip,
    this.tooltipSize,
    this.onTap,
  });
}

class TutorialOverlayWidget extends StatefulWidget {
  final TutorialEnum tutorial;
  final List<TutorialStep> steps;

  const TutorialOverlayWidget({
    required this.tutorial,
    required this.steps,
    super.key,
  });

  @override
  State<TutorialOverlayWidget> createState() => _TutorialOverlayWidgetState();
}

class _TutorialOverlayWidgetState extends State<TutorialOverlayWidget> {
  final ValueNotifier<bool> _visible = ValueNotifier<bool>(false);
  late final Queue<TutorialStep> _setQueue;

  /// The current step in the tutorial
  TutorialStep? _currentStep;

  /// The current highlighted rect for this step in the tutorial
  Rect? _currentRect;

  @override
  void initState() {
    super.initState();
    _setQueue = Queue.of(widget.steps);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _visible.value = true;
      _setNextAnchor();
      _schedulePositionCheck();
    });
  }

  @override
  void dispose() {
    _visible.dispose();
    TutorialOverlayOrchestrator.instance.onCloseTutorial(widget.tutorial);
    super.dispose();
  }

  Duration get _duration => FluffyThemes.animationDuration;

  Size get _tooltipSize => _currentStep?.tooltipSize ?? Size(300.0, 100.0);

  double? get _tooltipLeftOffset {
    final rect = _currentRect;
    if (rect == null) return null;

    return (rect.left + (rect.width / 2) - (_tooltipSize.width / 2)).clamp(
      8.0,
      MediaQuery.sizeOf(context).width - _tooltipSize.width - 8.0,
    );
  }

  /// Returns the top offset for the tooltip. Shows below the target widget if
  /// there is enough vertical space, otherwise shows above it.
  double? get _tooltipTopOffset {
    final rect = _currentRect;
    if (rect == null) return null;

    final screenHeight = MediaQuery.sizeOf(context).height;
    final spaceBelow = screenHeight - rect.bottom - 8.0;
    if (spaceBelow >= _tooltipSize.height) {
      return rect.bottom + 8.0;
    }
    return rect.top - _tooltipSize.height - 8.0;
  }

  /// Re-read the target widget's position every frame and snap the cutout to
  /// follow it whenever it moves (e.g. due to scroll, layout shift, animation).
  /// The loop is self-terminating once the widget is unmounted.
  void _schedulePositionCheck() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkAndUpdatePosition();
      _schedulePositionCheck();
    });
  }

  void _checkAndUpdatePosition() {
    // Don't interfere while a step-transition animation is in progress.
    if (_currentStep == null) return;

    final renderBox =
        _currentStep!.targetKey.currentContext?.findRenderObject()
            as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final newRect = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      renderBox.size.width,
      renderBox.size.height,
    );

    if (newRect != _currentRect) {
      setState(() {
        _currentRect = newRect;
      });
    }
  }

  Future<void> _close() async {
    _visible.value = false;
    await Future.delayed(_duration);
    if (mounted) {
      TutorialOverlayOrchestrator.instance.closeTutorial(
        tutorial: widget.tutorial,
      );
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

    if (!_visible.value) {
      _visible.value = true;
    }

    final offset = newRenderBox.localToGlobal(Offset.zero);
    final newRect = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      newRenderBox.size.width,
      newRenderBox.size.height,
    );

    setState(() {
      _currentStep = newStep;
      _currentRect = newRect;
    });
  }

  Future<void> _onTap(TapDownDetails details) async {
    final tapPos = details.globalPosition;
    if (_currentRect == null || !_currentRect!.contains(tapPos)) return;

    if (_currentStep?.onTap != null) {
      _visible.value = false;
      await Future.wait([
        _currentStep!.onTap!.call(),
        Future.delayed(_duration),
      ]);
    }
    _setNextAnchor();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _visible,
      builder: (context, visible, child) {
        return Stack(
          children: [
            AnimatedOpacity(
              opacity: visible ? 1.0 : 0.0,
              duration: _duration,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: _onTap,
                  child: CustomPaint(
                    painter: CutoutBackgroundPainter(
                      holeRect: _currentRect,
                      borderRadius: _currentStep?.borderRadius ?? 16.0,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            if (visible &&
                _currentStep?.tooltip != null &&
                _currentRect != null)
              Positioned(
                left: _tooltipLeftOffset,
                top: _tooltipTopOffset,
                child: Material(
                  color: Colors.transparent,
                  elevation: 4,
                  child: SizedBox(
                    width: _tooltipSize.width,
                    height: _tooltipSize.height,
                    child: _currentStep!.tooltip!,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
