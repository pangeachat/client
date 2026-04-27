import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay_controller.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_step_model.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_tooltip_container_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TutorialOverlayWidget extends StatefulWidget {
  final TutorialOverlayState model;

  final VoidCallback forward;
  final VoidCallback back;
  final VoidCallback reset;
  final Function(bool) setTutorialTransitioning;

  final bool enabledForward;
  final bool enabledBack;

  final int completedSteps;
  final int totalSteps;

  const TutorialOverlayWidget({
    required this.model,
    required this.forward,
    required this.back,
    required this.reset,
    required this.setTutorialTransitioning,
    required this.enabledForward,
    required this.enabledBack,
    required this.completedSteps,
    required this.totalSteps,
    super.key,
  });

  @override
  State<TutorialOverlayWidget> createState() => _TutorialOverlayWidgetState();
}

class _TutorialOverlayWidgetState extends State<TutorialOverlayWidget> {
  bool _visible = false;

  Size? _lastTargetSize;
  Offset? _lastTargetOffset;

  @override
  void initState() {
    super.initState();

    final model = widget.model;
    final tutorial = model.activeTutorial;

    if (tutorial == null) {
      ErrorHandler.logError(
        e: "TutorialOverlayWidget launched with no active tutorial",
        data: model.toJson(),
      );
      widget.reset();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setVisible(true);
    });
    WidgetsBinding.instance.addPostFrameCallback(_monitorTargetWidget);
  }

  /// Polls each frame while the overlay is active.
  /// If the current step's target widget has been unmounted (and we are not
  /// mid-transition), closes the overlay so the dark blocking layer does not
  /// remain visible without any tutorial content.
  void _monitorTargetWidget(Duration _) {
    if (!mounted) return;

    final tutorial = widget.model.activeTutorial;

    if (tutorial == null) {
      WidgetsBinding.instance.addPostFrameCallback(_monitorTargetWidget);
      return;
    }

    final stepKey = tutorial.targetKeyAt(widget.model.stepIndex);
    final renderBox = _currentRenderBox(stepKey);

    if (renderBox == null) {
      _lastTargetOffset = null;
      _lastTargetSize = null;

      final notTransitioning = !widget.model.isStepTransitioning;
      if (notTransitioning && _visible) {
        widget.reset();
        return;
      }
    } else {
      final newSize = renderBox.size;
      final newOffset = renderBox.localToGlobal(Offset.zero);

      final sizeChanged = newSize != _lastTargetSize;
      final offsetChanged = newOffset != _lastTargetOffset;

      if (sizeChanged || offsetChanged) {
        _lastTargetSize = newSize;
        _lastTargetOffset = newOffset;
        setState(() {});
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(_monitorTargetWidget);
  }

  Duration get _duration => FluffyThemes.animationDuration;

  static const double _tooltipPadding = 8.0;

  Size _tooltipSize(Size? tooltipSize) {
    final baseSize = tooltipSize ?? const Size(300, 100);
    return Size(
      baseSize.width + _tooltipPadding,
      baseSize.height + _tooltipPadding,
    );
  }

  RenderBox? _currentRenderBox(String? stepKey) {
    if (stepKey == null) return null;

    try {
      final target = MatrixState.pAnyState.layerLinkAndKey(stepKey);
      final renderBox =
          target.key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached || !renderBox.hasSize) {
        return null;
      }
      return renderBox;
    } catch (e) {
      ErrorHandler.logError(
        e: "Error finding render box for tutorial step with key $stepKey: $e",
        data: {},
      );
      return null;
    }
  }

  bool _tooltipHasBottomOverflow(String? stepKey, Size? tooltipSize) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final pos = _lastTargetOffset ?? Offset.zero;
    final targetSize = _lastTargetSize ?? Size.zero;
    final tip = _tooltipSize(tooltipSize);
    final tooltipOffset =
        pos.dy + targetSize.height + tip.height + (_tooltipPadding * 2);
    return tooltipOffset > screenHeight;
  }

  bool _tooltipHasTopOverflow(String? stepKey, Size? tooltipSize) {
    final pos = _lastTargetOffset ?? Offset.zero;
    final tip = _tooltipSize(tooltipSize);
    final tooltipOffset = pos.dy - tip.height - (_tooltipPadding * 2);
    return tooltipOffset < 0;
  }

  bool _showAbove(String? stepKey, Size? tooltipSize) =>
      !_tooltipHasTopOverflow(stepKey, tooltipSize) ||
      _tooltipHasBottomOverflow(stepKey, tooltipSize);

  double? _tooltipHorizontalOffset(String? stepKey, Size? tooltipSize) {
    final size = _lastTargetSize;
    final pos = _lastTargetOffset;

    if (pos == null || size == null) return null;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final tip = _tooltipSize(tooltipSize);
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

  void _setVisible(bool visible) {
    if (_visible == visible) return;
    if (mounted) {
      setState(() => _visible = visible);
    }
  }

  Future<void> _next(TutorialStep step) async {
    final success = await _executeStepCallback(step);
    if (success) widget.forward();
  }

  Future<void> _previous() async {
    await Future.delayed(_duration);
    widget.back();
  }

  Future<bool> _executeStepCallback(TutorialStep step) async {
    if (widget.model.isStepTransitioning) return false;
    try {
      _setVisible(false);
      widget.setTutorialTransitioning(true);

      final onTap = step.data.onTap;
      if (onTap != null) {
        await Future.wait([onTap.call(), Future.delayed(_duration)]);
      } else {
        await Future.delayed(_duration);
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: "Error executing tutorial step callback",
        s: s,
        data: {"stepType": step.type.name, "stepIndex": step.index},
      );
      return false;
    } finally {
      widget.setTutorialTransitioning(false);
      _setVisible(true);
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final tutorial = model.activeTutorial;
    final stepIndex = model.stepIndex;
    final step = tutorial?.step(stepIndex, L10n.of(context));

    final stepKey = tutorial?.targetKeyAt(widget.model.stepIndex);
    final stepSize = tutorial?.tooltipSizeAt(stepIndex);

    final showNavigation =
        tutorial?.tutorialType.showNavigationButtons ?? false;

    final size = _lastTargetSize;
    final holeWidth = (size?.width ?? 0.0) + (step?.style.padding ?? 0) * 2;
    final holeHeight = (size?.height ?? 0.0) + (step?.style.padding ?? 0) * 2;
    final showAbove = _showAbove(stepKey, stepSize);

    return MouseRegion(
      cursor: step != null && _visible
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: step != null && _visible ? () => _next(step) : null,
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
                            link: MatrixState.pAnyState
                                .layerLinkAndKey(step.data.targetKey)
                                .link,
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
                link: MatrixState.pAnyState
                    .layerLinkAndKey(step.data.targetKey)
                    .link,
                showWhenUnlinked: false,
                targetAnchor: showAbove
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                followerAnchor: showAbove
                    ? Alignment.bottomCenter
                    : Alignment.topCenter,
                offset: Offset(
                  _tooltipHorizontalOffset(stepKey, stepSize) ?? 0,
                  showAbove
                      ? -_tooltipPadding
                      : _tooltipPadding, // gap between target and tooltip
                ),
                child: TutorialTooltipContainerWidget(
                  width: step.style.tooltipSize.width,
                  height: step.style.tooltipSize.height,
                  padding: _tooltipPadding,
                  onNext: () => _next(step),
                  onPrevious: _previous,
                  showNext: showNavigation && widget.enabledForward,
                  showPrevious: showNavigation && widget.enabledBack,
                  currentStep: widget.completedSteps,
                  totalSteps: widget.totalSteps,
                  text: step.style.tooltip,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
