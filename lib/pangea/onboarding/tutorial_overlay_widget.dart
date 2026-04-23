import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_model.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay_orchestrator.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_step_model.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_tooltip_container_widget.dart';

enum TooltipPosition { above, below }

class TutorialOverlayWidget extends StatefulWidget {
  final TutorialModel tutorial;
  final TooltipPosition preferredPosition;
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

  bool _completedAllSteps = false;
  bool _handledClose = false;

  static const double _tooltipPadding = 8.0;

  @override
  void initState() {
    super.initState();

    _currentStepIndex = widget.initialStepIndex.clamp(
      0,
      widget.tutorial.tutorialType.stepCount - 1,
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
    if (!_handledClose) {
      TutorialOverlayController.instance.handleUnexpectedClose(
        completed: _completedAllSteps,
      );
    }
    super.dispose();
  }

  int get _stepsLength => widget.tutorial.tutorialType.stepCount;

  TutorialStep? get _currentStep =>
      _currentStepIndex >= 0 && _currentStepIndex < _stepsLength
      ? widget.tutorial.step(_currentStepIndex, L10n.of(context))
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
    final size = _currentSize;
    final pos = _currentOffset;

    if (pos == null || size == null) return null;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final tip = _tooltipSize;
    if (tip.width >= screenWidth) {
      return null; // can't fit, just center
    }

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

  bool get _hasPreviousTutorial =>
      _currentStepIndex > 0 ||
      TutorialOverlayController.instance.hasPreviousTutorial;

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
    if (!TutorialOverlayController.instance.hasPreviousTutorial) {
      // No previous tutorial — fall back to closing the sequence.
      await _close();
      return;
    }
    setState(() => _visible = false);
    await Future.delayed(_duration);
    if (mounted) {
      TutorialOverlayController.instance.launchPreviousTutorial();
    }
  }

  Future<void> _updateStep(int updatedIndex) async {
    Logs().i("Updating tutorial step to index $updatedIndex");
    if (updatedIndex < 0 || updatedIndex >= _stepsLength) {
      _completedAllSteps = updatedIndex >= _stepsLength;
      await _close();
      return;
    }

    if (mounted) {
      setState(() {
        _visible = true;
        _currentStepIndex = updatedIndex;
      });
    }

    widget.tutorial.tutorialType.saveProgress(updatedIndex + 1);
  }

  Future<void> _executeStepCallback() async {
    if (_transitioning) return;

    try {
      _transitioning = true;
      TutorialOverlayController.instance.beginStepTransition();

      final onTap = _currentStep?.data.onTap;

      if (onTap != null) {
        setState(() => _visible = false);
        await Future.wait([onTap.call(), Future.delayed(_duration)]);
      }

      await _next();
    } catch (e, s) {
      Logs().e('Error executing tutorial step callback: $e\n$s');
      await _close();
    } finally {
      _transitioning = false;
      TutorialOverlayController.instance.endStepTransition();
    }
  }

  Future<void> _close() async {
    if (!mounted) return;

    setState(() {
      _handledClose = true;
      _visible = false;
    });

    await Future.delayed(_duration);
    if (mounted) {
      TutorialOverlayController.instance.completeTutorial(
        widget.tutorial.tutorialType,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _currentStep;
    final showAbove = _showAbove;

    final completedStepsOffset =
        TutorialOverlayController.instance.completedStepsOffset;

    final currentStep = completedStepsOffset + _currentStepIndex + 1;

    final totalSteps =
        TutorialOverlayController.instance.totalStepsInCurrentSequence;

    final showNavigation = widget.tutorial.tutorialType.showNavigationButtons;

    final size = _currentSize;
    final holeWidth = (size?.width ?? 0.0) + (step?.style.padding ?? 0) * 2;
    final holeHeight = (size?.height ?? 0.0) + (step?.style.padding ?? 0) * 2;

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
                              width: holeWidth,
                              height: holeHeight,
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
                  showNext: showNavigation,
                  showPrevious: showNavigation && _hasPreviousTutorial,
                  currentStep: currentStep,
                  totalSteps: totalSteps,
                  text: step.style.tooltip,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
