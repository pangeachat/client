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
  final Widget tooltip;
  final Size tooltipSize;
  final Future<void> Function()? onTap;

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
        _showNextStep();
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

  Size get _tooltipSize {
    final baseSize = _currentStep?.tooltipSize ?? const Size(300, 100);
    return Size(baseSize.width + 8.0, baseSize.height + 12.0);
  }

  bool get _tooltipHasBottomOverflow {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final pos = _currentOffset ?? Offset.zero;
    final targetSize = _currentSize ?? Size.zero;
    final tip = _tooltipSize;
    final tooltipOffset = pos.dy + targetSize.height + 8.0 + tip.height;
    return tooltipOffset > screenHeight;
  }

  double? get _tooltipHorizontalOffset {
    if (_currentOffset == null || _currentSize == null) return null;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final tip = _tooltipSize;
    if (tip.width >= screenWidth) {
      return null; // can't fit, just center
    }
    final pos = _currentOffset!;
    final size = _currentSize!;
    final midpoint = pos.dx + size.width / 2;

    final rightEdge = midpoint + tip.width / 2;
    final leftEdge = midpoint - tip.width / 2;
    if (rightEdge > screenWidth) {
      return screenWidth - rightEdge - 8.0; // 8 is the gap
    }

    // then check for overflow on the left
    if (leftEdge < 8.0) {
      return 8.0 - leftEdge; // 8 is the gap
    }
    return null;
  }

  Future<void> _showNextStep() async {
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

  Future<void> _close() async {
    _visible.value = false;

    await Future.delayed(_duration);

    if (mounted) {
      TutorialOverlayOrchestrator.instance.closeTutorial(
        tutorial: widget.tutorial,
      );
    }
  }

  Future<void> _onTap() async {
    if (_currentStep?.onTap != null) {
      _visible.value = false;

      await Future.wait([
        _currentStep!.onTap!.call(),
        Future.delayed(_duration),
      ]);
    }

    _showNextStep();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _visible,
      builder: (context, visible, _) {
        final step = _currentStep;
        final hasBottomOverflow = _tooltipHasBottomOverflow;

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
                                onTapDown: (_) => _onTap(),
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
                targetAnchor: hasBottomOverflow
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                followerAnchor: hasBottomOverflow
                    ? Alignment.bottomCenter
                    : Alignment.topCenter,
                offset: Offset(
                  _tooltipHorizontalOffset ?? 0,
                  hasBottomOverflow
                      ? -8.0
                      : 8.0, // gap between target and tooltip
                ),
                child: Material(
                  color: Colors.transparent,
                  elevation: 4,
                  child: SizedBox(
                    width: _tooltipSize.width,
                    height: _tooltipSize.height,
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: step.tooltipSize.width,
                            height: step.tooltipSize.height,
                            child: step.tooltip,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: ElevatedButton(
                            onPressed: _onTap,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(56, 24),
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                            ),
                            child: Text(
                              "Next",
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                  ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          child: ElevatedButton(
                            onPressed: _onTap,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(56, 24),
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSecondary,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.secondary,
                            ),
                            child: Text(
                              "Previous",
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSecondary,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
