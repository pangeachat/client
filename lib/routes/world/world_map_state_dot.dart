import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

class WorldMapDot extends StatefulWidget {
  final QuestActivityCard card;
  final ActivityPinState state;
  final PinTier tier;
  final VoidCallback onTap;
  final bool pinged;
  final double fill;

  /// When true, the activity is focused (its detail panel is open): the dot
  /// draws a distinct focus ring (primary-coloured halo with a gap) around its
  /// state-coloured body, persistent through zoom/pan and cleared when the
  /// panel closes or another activity is focused (#7349). Decoupled from the
  /// colour state and progress fill. See world-map.instructions.md.
  final bool isFocused;

  /// When true, the pin plays its exit animation (scale → 0) then calls
  /// [onExited]. The parent keeps the widget in the tree until [onExited] fires.
  final bool dying;
  final VoidCallback? onExited;

  const WorldMapDot({
    super.key,
    required this.card,
    required this.state,
    required this.tier,
    required this.onTap,
    required this.pinged,
    this.fill = 0,
    this.isFocused = false,
    this.dying = false,
    this.onExited,
  });

  @override
  State<WorldMapDot> createState() => _WorldMapDotState();
}

class _WorldMapDotState extends State<WorldMapDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (!widget.dying) _ctrl.forward();
  }

  @override
  void didUpdateWidget(WorldMapDot old) {
    super.didUpdateWidget(old);
    if (widget.dying && !old.dying) {
      _ctrl.reverse().then((_) => widget.onExited?.call());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      child: Tooltip(
        message: widget.card.title,
        // Semantics below names the pin; exclude the Tooltip so the title isn't
        // announced twice ("<title> <title>").
        excludeFromSemantics: true,
        child: Semantics(
          button: !widget.dying,
          label: widget.dying
              ? ''
              : L10n.of(context).activityLabel(widget.card.title),
          excludeSemantics: true,
          child: GestureDetector(
            onTap: widget.dying ? null : widget.onTap,
            child: widget.tier == PinTier.mid
                ? _MediumDotContent(
                    state: widget.state,
                    pinged: widget.pinged,
                    fill: widget.fill,
                    isFocused: widget.isFocused,
                  )
                : _SmallDotContent(
                    state: widget.state,
                    fill: widget.fill,
                    isFocused: widget.isFocused,
                  ),
          ),
        ),
      ),
    );
  }
}

class _SmallDotContent extends StatelessWidget {
  final ActivityPinState state;
  final double fill;
  final bool isFocused;

  const _SmallDotContent({
    required this.state,
    this.fill = 0,
    this.isFocused = false,
  });

  @override
  Widget build(BuildContext context) => _WorldMapStateDot(
    state: state,
    diameter: PinSize.smallDiameter,
    borderWidth: 1.0,
    fill: fill,
    isFocused: isFocused,
  );
}

class _MediumDotContent extends StatelessWidget {
  final ActivityPinState state;
  final bool pinged;
  final double fill;
  final bool isFocused;

  const _MediumDotContent({
    required this.state,
    required this.pinged,
    this.fill = 0,
    this.isFocused = false,
  });

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    alignment: Alignment.center,
    children: [
      _WorldMapStateDot(
        state: state,
        diameter: 36,
        borderWidth: 2,
        fill: fill,
        isFocused: isFocused,
        glyph: const Icon(
          Icons.chat_bubble_outline,
          size: 18,
          color: Colors.white,
        ),
      ),
      if (pinged)
        Positioned(
          top: -2,
          right: -2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.back_hand,
              size: 12,
              color: Color(0xFF34A853),
            ),
          ),
        ),
    ],
  );
}

/// The pin body, keyed off the colour [state]:
///
///  - **inProgress** renders as a **gold star** (the state _is_ the progress),
///    sized by [fill] (0..1 — stars earned toward the total) between
///    [PinSize.progressStarMin] and [PinSize.progressStarMax], in place of the
///    coloured disc — never a disc + fill, so a progressed pin reads as a star;
///  - every other state renders as a [state]-coloured disc with a white border
///    and an optional [glyph] on top.
///
/// When [isFocused], a primary-coloured focus ring (a halo with a gap) wraps the
/// body, distinct from the white state-border (#7349). Progress is shown on the
/// dot only via the inProgress state; a joinable/joined pin that also has stars
/// shows the live colour here and its star row on the large card. Design:
/// world-map.instructions.md ("Goal Progress").
class _WorldMapStateDot extends StatelessWidget {
  final ActivityPinState state;
  final double diameter;
  final double borderWidth;
  final double fill;
  final bool isFocused;
  final Widget? glyph;

  const _WorldMapStateDot({
    required this.state,
    required this.diameter,
    required this.borderWidth,
    this.fill = 0,
    this.isFocused = false,
    this.glyph,
  });

  @override
  Widget build(BuildContext context) {
    final Widget dot;
    final double bodyDiameter;
    if (state == ActivityPinState.inProgress) {
      // Progress is the state: a gold star replaces the dot, growing with the
      // fraction of stars earned within the tuning bounds.
      bodyDiameter =
          PinSize.progressStarMin +
          (PinSize.progressStarMax - PinSize.progressStarMin) *
              fill.clamp(0.0, 1.0);
      dot = Icon(
        Icons.star,
        size: bodyDiameter,
        color: AppConfig.gold,
        shadows: const [Shadow(blurRadius: 3, color: Colors.black38)],
      );
    } else {
      bodyDiameter = diameter;
      dot = Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          color: state.color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: borderWidth),
          boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
        ),
        child: glyph == null ? null : Center(child: glyph),
      );
    }

    if (!isFocused) return dot;

    // The focus ring: a primary-coloured halo concentric with the disc, sitting
    // OUTSIDE the white state-border with a small transparent gap so the two
    // never blend — clearly the "I'm working with this one" marker, distinct
    // from the colour-state border at every tier. Drawn with a Stack +
    // Clip.none so it can overflow the fixed marker bounds without being
    // clipped, and a soft outer glow so it reads at the small-dot size (#7349).
    final primary = Theme.of(context).colorScheme.primary;
    const ringWidth = 2.5;
    const gap = 2.0;
    final ringDiameter = bodyDiameter + 2 * (gap + ringWidth);
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          width: ringDiameter,
          height: ringDiameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: primary, width: ringWidth),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.45),
                blurRadius: 5,
                spreadRadius: 0.5,
              ),
            ],
          ),
        ),
        dot,
      ],
    );
  }
}
