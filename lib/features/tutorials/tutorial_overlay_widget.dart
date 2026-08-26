import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_state_machine.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_tooltip_container_widget.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TutorialOverlayWidget extends StatefulWidget {
  final TutorialOverlayState model;

  final VoidCallback forward;
  final VoidCallback back;
  final VoidCallback reset;
  final VoidCallback decline;
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
    required this.decline,
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

  /// Where the current step's spotlights are on screen. Re-read every frame; a
  /// target whose widget has no attached render box simply contributes no hole.
  List<Rect> _spotlightRects = const [];

  @override
  void initState() {
    super.initState();

    if (widget.model.activeTutorial == null) {
      ErrorHandler.logError(
        e: "TutorialOverlayWidget launched with no active tutorial",
        data: widget.model.toJson(),
      );
      widget.reset();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _setVisible(true));
    WidgetsBinding.instance.addPostFrameCallback(_monitorTargetWidget);
  }

  TutorialStepData? get _stepData {
    final tutorial = widget.model.activeTutorial;
    if (tutorial == null) return null;
    return tutorial.dataAt(widget.model.stepIndex);
  }

  /// Polls each frame while the overlay is active, repositioning the spotlight
  /// as its targets move and deciding when the overlay has nothing left to
  /// point at.
  void _monitorTargetWidget(Duration _) {
    if (!mounted) return;

    final data = _stepData;
    if (data == null) {
      WidgetsBinding.instance.addPostFrameCallback(_monitorTargetWidget);
      return;
    }

    final rects = <Rect>[];
    for (final key in data.targetKeys) {
      final box = _currentRenderBox(key);
      if (box == null) continue;
      rects.add(box.localToGlobal(Offset.zero) & box.size);
    }
    final hostRects = data.spotlightRects?.call();
    if (hostRects != null) rects.addAll(hostRects);

    // A step with no spotlight to lose says for itself when it stops applying.
    if (data.surfaceIsVisible?.call() == false &&
        !widget.model.isStepTransitioning &&
        _visible) {
      widget.reset();
      return;
    }

    // A step with no targets is about the app rather than anything on screen,
    // so there is nothing that can vanish out from under it.
    if (data.hasSpotlight && rects.isEmpty) {
      // Every target is gone. A multi-target step survives losing some of them
      // — only losing all of them means there is nothing left to light.
      final notTransitioning = !widget.model.isStepTransitioning;
      if (notTransitioning && _visible) {
        // Armed steps included: the learner has navigated away to do the thing
        // the step asked for, so the overlay gets out of the way. The
        // controller keeps watching, and the tutorial resumes when they've
        // done it.
        widget.reset();
        return;
      }
    }

    if (!_sameRects(rects, _spotlightRects)) {
      setState(() => _spotlightRects = rects);
    }

    WidgetsBinding.instance.addPostFrameCallback(_monitorTargetWidget);
  }

  bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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

  RenderBox? _currentRenderBox(String stepKey) {
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

  /// The box containing everything the step lit — the target itself for a single
  /// one, the group's bounds for several.
  Rect? get _anchorRect {
    if (_spotlightRects.isEmpty) return null;
    return _spotlightRects.reduce((a, b) => a.expandToInclude(b));
  }

  /// Where the tooltip goes, decided by whether there is room beside what was
  /// lit rather than by how many things were lit.
  ///
  /// Two stacked buttons have tight bounds and read best anchored just above
  /// them. Map pins scattered across the map have bounds spanning the viewport,
  /// leaving no room either side — that takes the bottom, so the card never
  /// covers what it just lit. A target as big as the map has the same problem,
  /// and anchoring it pushed the card clean off the top edge, which read as the
  /// step silently doing nothing. A step with nothing lit has no "beside" at
  /// all, so it centers.
  _TooltipPlacement _placementFor(Size tooltipSize, bool dimsBackground) {
    final anchor = _anchorRect;
    // An undimmed step has handed the surface over, so its card takes the bottom
    // rather than sitting in the middle of what the learner is meant to use.
    if (anchor == null) {
      return dimsBackground
          ? _TooltipPlacement.centered
          : _TooltipPlacement.bottom;
    }

    final fitsBelow =
        anchor.bottom + _gap(tooltipSize) <= MediaQuery.sizeOf(context).height;
    if (_showAbove(anchor, tooltipSize) || fitsBelow) {
      return _TooltipPlacement.anchored;
    }
    return _TooltipPlacement.bottom;
  }

  /// The vertical room one placement needs: the card plus the breathing space
  /// on both sides of it.
  double _gap(Size tooltipSize) =>
      _tooltipSize(tooltipSize).height + _tooltipPadding * 2;

  Rect _inflated(Rect rect, double? padding) =>
      padding == null ? rect : rect.inflate(padding);

  /// The single answer to "does the card fit above what was lit?" — [_placementFor]
  /// decides *whether* to anchor from it, and the placement widget then puts the
  /// card on that side.
  bool _showAbove(Rect anchor, Size tooltipSize) =>
      anchor.top - _gap(tooltipSize) >= 0;

  /// Left edge for a tooltip centered on [anchor], nudged back inside the
  /// screen when centering would push it off either side.
  double _tooltipLeft(Rect anchor, Size tip) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (tip.width >= screenWidth) return 0;
    final centered = anchor.center.dx - tip.width / 2;
    return centered.clamp(
      _tooltipPadding,
      screenWidth - tip.width - _tooltipPadding,
    );
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
      final canShowNextStep = step.data.canShowNextStep;
      if (onTap != null) {
        await Future.wait([onTap.call(), Future.delayed(_duration)]);
      } else {
        await Future.delayed(_duration);
      }

      if (!canShowNextStep()) return false;
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

  /// On an armed step every tap belongs to the app, so this only decides
  /// whether the overlay should get out of the way: a tap on something it lit
  /// is the learner doing what was asked, so the spotlight stays until that
  /// lands; a tap anywhere else means they are doing something else, and the
  /// scrim should not follow them around. The step stays armed either way.
  void _onArmedPointerDown(Offset position) {
    if (!_visible) return;
    final onLitTarget = _spotlightRects.any(
      (rect) => rect.inflate(_tooltipPadding).contains(position),
    );
    if (!onLitTarget) widget.reset();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final tutorial = model.activeTutorial;
    final stepIndex = model.stepIndex;
    final step = tutorial?.step(stepIndex, L10n.of(context));
    final data = _stepData;

    if (step == null || data == null) return const SizedBox.shrink();

    final tooltipSize = step.style.tooltipSize;
    // A targetless step needs nothing measured; a spotlight step waits until it
    // knows where its target is, so the tooltip never flies in from the corner.
    final ready = !data.hasSpotlight || _spotlightRects.isNotEmpty;
    final showNavigation = step.type.showNavigationButtons;

    final content = Stack(
      children: [
        if (step.style.dimsBackground)
          AnimatedOpacity(
            opacity: _visible && ready ? 1.0 : 0.0,
            duration: _duration,
            child: ExcludeSemantics(
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Colors.black,
                  BlendMode.srcOut,
                ),
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(100),
                      ),
                    ),

                    /// One "hole" per lit target.
                    for (final rect in _spotlightRects)
                      Positioned.fromRect(
                        rect: _inflated(rect, step.style.padding),
                        child: Container(
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
              ),
            ),
          ),

        if (_visible && ready)
          _TutorialTooltipPlacement(
            placement: _placementFor(tooltipSize, step.style.dimsBackground),
            anchor: _anchorRect,
            showAbove:
                _anchorRect != null && _showAbove(_anchorRect!, tooltipSize),
            left: _anchorRect == null
                ? null
                : _tooltipLeft(_anchorRect!, _tooltipSize(tooltipSize)),
            padding: _tooltipPadding,
            child: TutorialTooltipContainerWidget(
              width: tooltipSize.width,
              height: tooltipSize.height,
              padding: _tooltipPadding,
              onNext: () => _next(step),
              onPrevious: _previous,
              showNext: showNavigation && widget.enabledForward,
              showPrevious: showNavigation && widget.enabledBack,
              currentStep: widget.completedSteps,
              totalSteps: widget.totalSteps,
              text: step.style.tooltip,
              choices: step.style.choices,
              wordBubble: data.wordBubble?.call(),
              onChoice: (outcome) => switch (outcome) {
                TutorialChoiceOutcome.advance => _next(step),
                TutorialChoiceOutcome.decline => widget.decline(),
              },
            ),
          ),
      ],
    );

    // An undimmed step is purely the card: nothing is blocked, and no tap
    // dismisses it, so the nudge stands until the learner does the thing or
    // leaves the surface. Not wrapped in BlockSemantics for the same reason the
    // armed case isn't — hiding the surface from a screen reader while asking
    // the learner to use it is the trap.
    if (!step.style.dimsBackground) {
      return IgnorePointer(child: content);
    }

    // An armed step hands the screen back: the learner has to reach the thing
    // the step is pointing at, so the overlay must not swallow their taps. It
    // watches them only to know when to get out of the way, and it does not
    // block assistive tech either — telling someone to tap a pin while hiding
    // that pin from their screen reader is the trap this avoids.
    if (data.isArmed) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => _onArmedPointerDown(event.position),
        child: IgnorePointer(child: content),
      );
    }

    // A branch step is asking a question, so a tap anywhere but its buttons
    // does nothing — otherwise a tap aimed at a button that just misses would
    // advance past the question.
    final tapAdvances = _visible && !step.style.isBranch;

    return BlockSemantics(
      child: MouseRegion(
        cursor: tapAdvances
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tapAdvances ? () => _next(step) : null,
          child: content,
        ),
      ),
    );
  }
}

enum _TooltipPlacement { anchored, centered, bottom }

/// Places the tooltip per [_TutorialOverlayWidgetState._placement].
class _TutorialTooltipPlacement extends StatelessWidget {
  final _TooltipPlacement placement;
  final Rect? anchor;
  final bool showAbove;
  final double? left;
  final double padding;
  final Widget child;

  const _TutorialTooltipPlacement({
    required this.placement,
    required this.anchor,
    required this.showAbove,
    required this.left,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final anchor = this.anchor;
    if (placement != _TooltipPlacement.anchored || anchor == null) {
      return Align(
        alignment: placement == _TooltipPlacement.bottom
            ? Alignment.bottomCenter
            : Alignment.center,
        child: Padding(padding: EdgeInsets.all(padding * 2), child: child),
      );
    }

    return Positioned(
      left: left,
      top: showAbove ? null : anchor.bottom + padding,
      bottom: showAbove
          ? MediaQuery.sizeOf(context).height - anchor.top + padding
          : null,
      child: child,
    );
  }
}
