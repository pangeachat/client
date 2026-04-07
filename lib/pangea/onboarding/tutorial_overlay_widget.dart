import 'dart:collection';

import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_model.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay_orchestrator.dart';

class TutorialStep {
  final LayerLink targetLink;
  final GlobalKey targetKey;
  final Future<void> Function()? onTap;
  final Widget tooltip;
  final Size tooltipSize;

  final double? borderRadius;
  final double? padding;

  const TutorialStep({
    required this.targetLink,
    required this.targetKey,
    required this.tooltip,
    required this.tooltipSize,
    this.onTap,
    this.borderRadius,
    this.padding,
  });
}

class TutorialOverlayWidget extends StatefulWidget {
  final TutorialModel tutorial;

  const TutorialOverlayWidget({required this.tutorial, super.key});

  @override
  State<TutorialOverlayWidget> createState() => _TutorialOverlayWidgetState();
}

class _TutorialOverlayWidgetState extends State<TutorialOverlayWidget> {
  final ValueNotifier<bool> _visible = ValueNotifier(false);
  late final Queue<TutorialStep> _setQueue;

  /// The current step in the tutorial
  TutorialStep? _currentStep;

  /// The size of the current step's underlying widget
  Size? _currentSize;

  /// The global position of the current step's underlying widget
  Offset? _currentOffset;

  @override
  void initState() {
    super.initState();
    _setQueue = Queue.of(widget.tutorial.steps);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _visible.value = true;
        _setNextAnchor();
      }
    });
  }

  @override
  void dispose() {
    _visible.dispose();

    TutorialOverlayOrchestrator.instance.onCloseTutorial(
      widget.tutorial.tutorialType,
    );

    super.dispose();
  }

  Duration get _duration => FluffyThemes.animationDuration;

  Size get _tooltipSize => _currentStep?.tooltipSize ?? const Size(300, 100);

  Offset _tooltipOffset(BuildContext context) {
    const gap = 8.0;
    final screen = MediaQuery.of(context).size;
    final pos = _currentOffset ?? Offset.zero;
    final targetSize = _currentSize ?? Size.zero;
    final tip = _tooltipSize;

    // Prefer below; flip above if it would go off the bottom
    final double dy =
        pos.dy + targetSize.height + gap + tip.height <= screen.height
        ? targetSize.height + gap
        : -tip.height - gap;

    // Clamp horizontally so tooltip stays within screen
    double dx = 0;
    final rightEdge = pos.dx + tip.width;
    if (rightEdge > screen.width) {
      dx = screen.width - pos.dx - tip.width - gap;
    }
    if (pos.dx + dx < gap) {
      dx = gap - pos.dx;
    }

    return Offset(dx, dy);
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
    Logs().i(
      "Setting next anchor for tutorial ${widget.tutorial.tutorialType}",
    );
    Logs().i("Current queue length: ${_setQueue.length}");
    if (_setQueue.isEmpty) {
      await _close();
      return;
    }

    final TutorialStep newStep = _setQueue.removeFirst();
    final renderBox =
        newStep.targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) {
      ErrorHandler.logError(
        e: "Could not find render box for tutorial step with key ${newStep.targetKey}",
        data: {},
      );
      await _close();
      return;
    }

    if (!_visible.value) {
      _visible.value = true;
    }

    Logs().i(
      "Setting next anchor for tutorial ${widget.tutorial.tutorialType} to ${newStep.targetKey}",
    );

    setState(() {
      _currentStep = newStep;
      _currentSize = renderBox.size;
      _currentOffset = renderBox.localToGlobal(Offset.zero);
    });
  }

  Future<void> _onTap(TapDownDetails details) async {
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
        final step = _currentStep;

        return Stack(
          children: [
            AnimatedOpacity(
              opacity: visible && step != null ? 1.0 : 0.0,
              duration: _duration,
              child: step != null
                  ? ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Colors.black,
                        BlendMode.srcOut,
                      ),
                      child: Stack(
                        children: [
                          /// Overlay + layer
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(100),
                            ),
                          ),

                          /// The "hole"
                          CompositedTransformFollower(
                            link: step.targetLink,
                            showWhenUnlinked: false,
                            targetAnchor: Alignment.center,
                            followerAnchor: Alignment.center,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTapDown: _onTap,
                                child: Container(
                                  width:
                                      (_currentSize?.width ?? 0.0) +
                                      (step.padding ?? 0) * 2,
                                  height:
                                      (_currentSize?.height ?? 0.0) +
                                      (step.padding ?? 0) * 2,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(
                                      step.borderRadius ?? 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            if (visible && step != null)
              CompositedTransformFollower(
                link: step.targetLink,
                showWhenUnlinked: false,
                offset: _tooltipOffset(context),
                child: Material(
                  color: Colors.transparent,
                  elevation: 4,
                  child: SizedBox(
                    width: _tooltipSize.width,
                    height: _tooltipSize.height,
                    child: step.tooltip,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
