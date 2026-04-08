import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_model.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay_orchestrator.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_tooltip_container_widget.dart';

enum TooltipPosition { above, below }

class TutorialOverlayWidget extends StatefulWidget {
  final TutorialModel tutorial;
  final TooltipPosition preferredPosition;

  /// The step index to start on. Defaults to 0 (first step). Pass
  /// `tutorialType.stepCount - 1` when the user navigated back to this model.
  final int initialStepIndex;

  const TutorialOverlayWidget({
    required this.tutorial,
    this.preferredPosition = TooltipPosition.above,
    this.initialStepIndex = 0,
    super.key,
  });

  @override
  State<TutorialOverlayWidget> createState() => _TutorialOverlayWidgetState();
}

class _TutorialOverlayWidgetState extends State<TutorialOverlayWidget> {
  late int _currentStepIndex;
  bool _transitioning = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _currentStepIndex = widget.initialStepIndex.clamp(
      0,
      widget.tutorial.steps.length - 1,
    );
    Logs().i(
      "Initializing tutorial overlay for tutorial ${widget.tutorial.tutorialType} at step $_currentStepIndex",
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _visible = true;
        _updateStep(_currentStepIndex);
      }
    });
  }

  @override
  void dispose() {
    TutorialOverlayOrchestrator.instance.onCloseTutorial(
      widget.tutorial.tutorialType,
    );
    super.dispose();
  }

  static const double _tooltipPadding = 8.0;

  int get _stepsLength => widget.tutorial.steps.length;

  TutorialStep? get _currentStep =>
      _currentStepIndex >= 0 && _currentStepIndex < _stepsLength
      ? widget.tutorial.steps[_currentStepIndex]
      : null;

  Duration get _duration => FluffyThemes.animationDuration;

  Size get _tooltipSize {
    final baseSize = _currentStep?.style.tooltipSize ?? const Size(300, 100);
    return Size(
      baseSize.width + _tooltipPadding,
      baseSize.height + _tooltipPadding,
    );
  }

  RenderBox? get _currentRenderBox {
    final step = _currentStep;
    if (step == null) return null;
    final stepKey = step.data.targetKey;

    try {
      final renderBox =
          stepKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached || !renderBox.hasSize) {
        return null;
      }
      return renderBox;
    } catch (e) {
      ErrorHandler.logError(
        e: "Error finding render box for tutorial step with key $stepKey: $e",
        data: {"tutorialType": widget.tutorial.tutorialType.name},
      );
      return null;
    }
  }

  Size? get _currentSize => _currentRenderBox?.size;

  Offset? get _currentOffset => _currentRenderBox?.localToGlobal(Offset.zero);

  bool get _tooltipHasBottomOverflow {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final pos = _currentOffset ?? Offset.zero;
    final targetSize = _currentSize ?? Size.zero;
    final tip = _tooltipSize;
    final tooltipOffset =
        pos.dy + targetSize.height + tip.height + (_tooltipPadding * 2);
    return tooltipOffset > screenHeight;
  }

  bool get _tooltipHasTopOverflow {
    final pos = _currentOffset ?? Offset.zero;
    final tip = _tooltipSize;
    final tooltipOffset = pos.dy - tip.height - (_tooltipPadding * 2);
    return tooltipOffset < 0;
  }

  bool get _showAbove {
    final preferAbove = widget.preferredPosition == TooltipPosition.above;
    if (preferAbove) {
      // Show above unless top overflow forces below
      return !_tooltipHasTopOverflow || _tooltipHasBottomOverflow;
    } else {
      // Show below unless bottom overflow forces above
      return _tooltipHasBottomOverflow;
    }
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

    final rightEdge = midpoint + tip.width / 2 + _tooltipPadding;
    final leftEdge = midpoint - tip.width / 2 - _tooltipPadding;
    if (rightEdge > screenWidth) {
      return screenWidth - rightEdge - _tooltipPadding;
    }

    // then check for overflow on the left
    if (leftEdge < 0) {
      return _tooltipPadding - leftEdge;
    }
    return null;
  }

  Future<void> _next() async {
    await _updateStep(_currentStepIndex + 1);
  }

  Future<void> _previous() async {
    if (_currentStepIndex == 0) {
      await _goBackToPreviousTutorial();
      return;
    }
    await _updateStep(_currentStepIndex - 1);
  }

  /// Closes the current tutorial overlay and signals the orchestrator to
  /// re-open the previous tutorial in the sequence at its last step.
  Future<void> _goBackToPreviousTutorial() async {
    if (!TutorialOverlayOrchestrator.instance.hasPreviousTutorial(
      widget.tutorial.tutorialType,
    )) {
      // No previous tutorial — fall back to closing the sequence.
      await _close();
      return;
    }
    setState(() => _visible = false);
    await Future.delayed(_duration);
    if (mounted) {
      TutorialOverlayOrchestrator.instance.requestGoBack(
        currentTutorial: widget.tutorial,
      );
    }
  }

  Future<void> _updateStep(int updatedIndex) async {
    Logs().i("Updating tutorial step to index $updatedIndex");
    if (updatedIndex < 0 || updatedIndex >= _stepsLength) {
      await _close();
      return;
    }

    setState(() {
      _visible = true;
      _currentStepIndex = updatedIndex;
    });
  }

  Future<void> _executeStepCallback() async {
    if (_transitioning) return;
    _transitioning = true;

    final onTap = _currentStep?.data.onTap;

    if (onTap != null) {
      setState(() => _visible = false);
      await Future.wait([onTap.call(), Future.delayed(_duration)]);
    }

    await _next();
    _transitioning = false;
  }

  Future<void> _close() async {
    setState(() => _visible = false);
    await Future.delayed(_duration);
    if (mounted) {
      TutorialOverlayOrchestrator.instance.closeTutorial(
        tutorial: widget.tutorial,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _currentStep;
    final showAbove = _showAbove;

    final completedStepsOffset =
        TutorialOverlayOrchestrator.instance.completedStepsOffset;

    final currentStep = completedStepsOffset + _currentStepIndex + 1;

    final totalSteps =
        TutorialOverlayOrchestrator.instance.totalStepsInCurrentSequence;

    return MouseRegion(
      cursor: step != null && _visible
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: step != null && _visible ? _executeStepCallback : null,
        child: Stack(
          children: [
            AnimatedOpacity(
              opacity: _visible && step != null ? 1.0 : 0.0,
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
                            link: step.data.targetLink,
                            showWhenUnlinked: false,
                            targetAnchor: Alignment.center,
                            followerAnchor: Alignment.center,
                            child: Container(
                              width:
                                  (_currentSize?.width ?? 0.0) +
                                  (step.style.padding ?? 0) * 2,
                              height:
                                  (_currentSize?.height ?? 0.0) +
                                  (step.style.padding ?? 0) * 2,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(
                                  step.style.borderRadius ?? 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            if (_visible && step != null)
              CompositedTransformFollower(
                link: step.data.targetLink,
                showWhenUnlinked: false,
                targetAnchor: showAbove
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                followerAnchor: showAbove
                    ? Alignment.bottomCenter
                    : Alignment.topCenter,
                offset: Offset(
                  _tooltipHorizontalOffset ?? 0,
                  showAbove
                      ? -_tooltipPadding
                      : _tooltipPadding, // gap between target and tooltip
                ),
                child: TutorialTooltipContainerWidget(
                  width: step.style.tooltipSize.width,
                  height: step.style.tooltipSize.height,
                  padding: _tooltipPadding,
                  onNext: _executeStepCallback,
                  onPrevious: _previous,
                  showPrevious:
                      _currentStepIndex > 0 ||
                      TutorialOverlayOrchestrator.instance.hasPreviousTutorial(
                        widget.tutorial.tutorialType,
                      ),
                  currentStep: currentStep,
                  totalSteps: totalSteps,
                  child: step.style.tooltip,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
