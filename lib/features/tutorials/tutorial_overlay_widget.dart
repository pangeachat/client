import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_state_machine.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_tooltip_container_widget.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TutorialOverlayWidget extends StatefulWidget {
  final TutorialOverlayState model;

  /// The running sequence's catalog identity: the card's title and whether it
  /// carries the sequence-wide Skip control. Null for an uncatalogued sequence.
  final TutorialSequenceKind? sequenceKind;

  final VoidCallback forward;
  final VoidCallback reset;
  final VoidCallback skipSequence;
  final Function(bool) setTutorialTransitioning;

  final int completedSteps;
  final int totalSteps;

  const TutorialOverlayWidget({
    required this.model,
    required this.sequenceKind,
    required this.forward,
    required this.reset,
    required this.skipSequence,
    required this.setTutorialTransitioning,
    required this.completedSteps,
    required this.totalSteps,
    super.key,
  });

  /// Whether this card carries the sequence-wide Skip control.
  ///
  /// Nearly every card does, so the way out sits in the same corner
  /// throughout a walkthrough. Four cards do not: an uncatalogued sequence (a
  /// test's) has nothing to skip out of, a branch's decline choice IS the
  /// skip, a step may opt out ([TutorialStepStyle.showsSkip] — the greeting),
  /// and a **one-step run** offers the learner nothing by it: skipping there
  /// is indistinguishable from finishing, which a tap anywhere already does.
  static bool showsSkip({
    required TutorialSequenceKind? sequenceKind,
    required TutorialStepStyle style,
    required int totalSteps,
  }) =>
      sequenceKind != null &&
      totalSteps > 1 &&
      !style.isBranch &&
      style.showsSkip;

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
    _scheduleMonitor();
  }

  @override
  void didUpdateWidget(TutorialOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.model;
    final now = widget.model;
    if (old.stepIndex != now.stepIndex ||
        old.activeTutorial?.tutorialType != now.activeTutorial?.tutorialType) {
      // The monitor measures post-frame, so the incoming step's first frame
      // would otherwise render against the OUTGOING step's rects — the card
      // and scrim hole flash at the previous target, then jump. Cleared, the
      // step shows nothing until it has been measured, and appears once, in
      // place.
      _spotlightRects = const [];
    }
  }

  /// Registers the next monitor pass AND asks for the frame that runs it.
  /// addPostFrameCallback alone does not schedule a frame, so on an idle
  /// screen the loop — and the "target vanished → tear down" check with it —
  /// simply stopped. Cost: a continuous frame while the overlay is up;
  /// accepted, the overlay is short-lived by design.
  void _scheduleMonitor() {
    WidgetsBinding.instance.addPostFrameCallback(_monitorTargetWidget);
    WidgetsBinding.instance.ensureVisualUpdate();
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
      _scheduleMonitor();
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

    _scheduleMonitor();
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
    // A step with no scrim is about the whole screen, so its card takes the
    // bottom rather than sitting in the middle of what it is describing.
    if (anchor == null) {
      return dimsBackground
          ? _TooltipPlacement.centered
          : _TooltipPlacement.screenBottom;
    }

    final fitsBelow =
        anchor.bottom + _gap(tooltipSize) <= MediaQuery.sizeOf(context).height;
    if (_showAbove(anchor, tooltipSize) || fitsBelow) {
      return _TooltipPlacement.anchored;
    }
    // Too big to sit beside — a panel, or the map. The card takes the bottom of
    // the TARGET, centred on it, not the bottom of the screen: a course panel
    // occupies one column, and a card centred on the screen there reads as
    // belonging to the map beside it.
    return _TooltipPlacement.anchorBottom;
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

  /// Completes the armed step. Reached two ways while the card is up: the
  /// learner's pointer landing inside the spotlight (it ALSO falls through and
  /// does the thing the step asked for), or a tap anywhere else, which only
  /// dismisses. Either way the step is done and marked seen — shown is seen —
  /// because leave-it-armed dismissal re-offered the card on every return
  /// visit, which read as the tutorial repeating itself. The arming still
  /// completes the step when the learner acts with the card NOT up (torn down
  /// by its surface unmounting, or preempted by another sequence).
  void _completeArmedStep() {
    if (!_visible) return;
    widget.forward();
  }

  Widget _buildScrim(TutorialStep step, bool ready) {
    return AnimatedOpacity(
      opacity: _visible && ready ? 1.0 : 0.0,
      duration: _duration,
      child: ExcludeSemantics(
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcOut),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(color: Colors.black.withAlpha(100)),
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
    );
  }

  /// The card, seated by [_placementFor]. [onCardTap] makes the card's body a
  /// tap surface of its own — an armed step passes it so a tap on the card
  /// dismisses like a tap on the scrim, instead of falling through the card
  /// onto whatever the barrier decides is underneath.
  Widget _buildTooltip(
    TutorialStep step,
    TutorialStepData data, {
    VoidCallback? onCardTap,
  }) {
    final tooltipSize = step.style.tooltipSize;
    final card = TutorialTooltipContainerWidget(
      width: tooltipSize.width,
      height: tooltipSize.height,
      padding: _tooltipPadding,
      sequenceKind: widget.sequenceKind,
      // See [TutorialOverlayWidget.showsSkip] for which cards carry it. On an
      // armed card it is a real click target like everywhere else: the card
      // sits above the armed step's pointer barrier.
      onSkip:
          TutorialOverlayWidget.showsSkip(
            sequenceKind: widget.sequenceKind,
            style: step.style,
            totalSteps: widget.totalSteps,
          )
          ? widget.skipSequence
          : null,
      currentStep: widget.completedSteps,
      totalSteps: widget.totalSteps,
      text: step.style.tooltip,
      choices: step.style.choices,
      wordBubble: data.wordBubble?.call(),
      onChoice: (outcome) => switch (outcome) {
        TutorialChoiceOutcome.advance => _next(step),
        TutorialChoiceOutcome.decline => widget.skipSequence(),
      },
    );

    return _TutorialTooltipPlacement(
      placement: _placementFor(tooltipSize, step.style.dimsBackground),
      anchor: _anchorRect,
      showAbove: _anchorRect != null && _showAbove(_anchorRect!, tooltipSize),
      left: _anchorRect == null
          ? null
          : _tooltipLeft(_anchorRect!, _tooltipSize(tooltipSize)),
      padding: _tooltipPadding,
      tooltipSize: _tooltipSize(tooltipSize),
      child: onCardTap == null
          ? card
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCardTap,
              child: card,
            ),
    );
  }

  /// An armed step hands back the lit target — and only the lit target. The
  /// learner has to reach the thing the step is pointing at themselves, so a
  /// pointer inside the spotlight falls through to the app (and completes the
  /// step on the way — see [_completeArmedStep]). Everywhere else the overlay
  /// behaves like an overlay: nothing under the scrim can be hovered or
  /// clicked, and a tap dismisses. It does not block assistive tech (no
  /// [BlockSemantics]) — telling someone to tap a role while hiding that role
  /// from their screen reader is the trap this avoids — and the barrier is
  /// excluded from semantics so AT never lands on an unlabeled tap surface.
  Widget _buildArmedStep(TutorialStep step, TutorialStepData data, bool ready) {
    final active = _visible && ready;
    return Stack(
      children: [
        if (step.style.dimsBackground)
          IgnorePointer(child: _buildScrim(step, ready)),
        if (active)
          Positioned.fill(
            child: ExcludeSemantics(
              child: _SpotlightPassthrough(
                // The same inflated rects the scrim cuts out, so what looks
                // lit and what is reachable cannot drift apart.
                holes: [
                  for (final rect in _spotlightRects)
                    _inflated(rect, step.style.padding),
                ],
                onHolePointerDown: _completeArmedStep,
                // The dismiss surface. No MouseRegion: the scrim reads as
                // inert background (default arrow), dismissal is an escape
                // hatch rather than a call to action.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _completeArmedStep,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        if (active) _buildTooltip(step, data, onCardTap: _completeArmedStep),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final tutorial = model.activeTutorial;
    final stepIndex = model.stepIndex;
    final step = tutorial?.step(stepIndex, L10n.of(context));
    final data = _stepData;

    if (step == null || data == null) return const SizedBox.shrink();

    // A targetless step needs nothing measured; a spotlight step waits until it
    // knows where its target is, so the tooltip never flies in from the corner.
    final ready = !data.hasSpotlight || _spotlightRects.isNotEmpty;

    if (data.isArmed) return _buildArmedStep(step, data, ready);

    final content = Stack(
      children: [
        if (step.style.dimsBackground) _buildScrim(step, ready),
        if (_visible && ready) _buildTooltip(step, data),
      ],
    );

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

/// The armed step's pointer barrier. Claims every pointer except those inside
/// a spotlight [holes] rect: those fall through to the lit target underneath,
/// observed on the way ([onHolePointerDown]) so the step completes on the
/// learner's first touch without ever stealing the touch itself. Only TAPS
/// fall through — scroll signals are claimed even inside a hole, because a
/// wheel over the lit target scrolled the surface under a held overlay, and
/// the learner could strand the target half off screen with no way back.
/// [child] is the dismiss surface for everything else — and because the
/// barrier claims those hits, hovers stop here too: nothing under the scrim
/// shows the cursor it would show if it were reachable.
class _SpotlightPassthrough extends SingleChildRenderObjectWidget {
  const _SpotlightPassthrough({
    required this.holes,
    required this.onHolePointerDown,
    required super.child,
  });

  /// Where pointers pass through, in global coordinates — the spotlight rects
  /// are measured global-side ([_TutorialOverlayWidgetState._spotlightRects]),
  /// and [_RenderSpotlightPassthrough] converts each hit back to global before
  /// comparing.
  final List<Rect> holes;

  final VoidCallback onHolePointerDown;

  @override
  _RenderSpotlightPassthrough createRenderObject(BuildContext context) =>
      _RenderSpotlightPassthrough(holes, onHolePointerDown);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSpotlightPassthrough renderObject,
  ) {
    renderObject
      ..holes = holes
      ..onHolePointerDown = onHolePointerDown;
  }
}

class _RenderSpotlightPassthrough extends RenderProxyBox {
  _RenderSpotlightPassthrough(this.holes, this.onHolePointerDown);

  /// Hit-test-only state: nothing is painted, so updates need no repaint.
  List<Rect> holes;
  VoidCallback onHolePointerDown;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final globalPosition = localToGlobal(position);
    if (holes.any((hole) => hole.contains(globalPosition))) {
      // Inside a hole: join the hit path (so [handleEvent] sees the pointer
      // going by) WITHOUT claiming it, so hit testing continues to the app
      // underneath — the same contract as [HitTestBehavior.translucent].
      result.add(BoxHitTestEntry(this, position));
      return false;
    }
    // Outside every hole: the child (the dismiss surface) claims the hit,
    // which is what blocks clicks and hovers from reaching under the scrim.
    return super.hitTest(result, position: position);
  }

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerDownEvent) onHolePointerDown();
    if (event is PointerScrollEvent) {
      // This entry precedes the app's in the hit path (the overlay is hit
      // first), so registering first wins the resolver and the scrollable
      // under the hole never scrolls. The no-op is the point: the signal is
      // claimed so nothing moves.
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
    }
  }
}

enum _TooltipPlacement {
  /// Just above or just below what was lit.
  anchored,

  /// The middle of the screen — a step with nothing lit, about the app.
  centered,

  /// The bottom of the screen — a step with nothing lit, about the screen.
  screenBottom,

  /// The bottom of what was lit, centred on it. For a target too big to sit
  /// beside: the card belongs to that surface, so it sits ON it rather than
  /// drifting to the middle of a screen the surface may occupy only half of.
  anchorBottom,
}

/// Places the tooltip per [_TutorialOverlayWidgetState._placementFor].
class _TutorialTooltipPlacement extends StatelessWidget {
  final _TooltipPlacement placement;
  final Rect? anchor;
  final bool showAbove;
  final double? left;
  final double padding;

  /// The card's measured size, needed to seat it INSIDE the anchor's bottom
  /// edge rather than hanging past it.
  final Size tooltipSize;
  final Widget child;

  const _TutorialTooltipPlacement({
    required this.placement,
    required this.anchor,
    required this.showAbove,
    required this.left,
    required this.padding,
    required this.tooltipSize,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final anchor = this.anchor;
    if (anchor == null ||
        placement == _TooltipPlacement.centered ||
        placement == _TooltipPlacement.screenBottom) {
      return Align(
        alignment: placement == _TooltipPlacement.screenBottom
            ? Alignment.bottomCenter
            : Alignment.center,
        child: Padding(padding: EdgeInsets.all(padding * 2), child: child),
      );
    }

    if (placement == _TooltipPlacement.anchorBottom) {
      final screenHeight = MediaQuery.sizeOf(context).height;
      // Clamped, so a target running past the bottom of the screen (or taller
      // than it) still leaves the whole card visible.
      final top = (anchor.bottom - tooltipSize.height - padding * 2).clamp(
        padding,
        (screenHeight - tooltipSize.height - padding).clamp(0.0, screenHeight),
      );
      return Positioned(left: left, top: top, child: child);
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
