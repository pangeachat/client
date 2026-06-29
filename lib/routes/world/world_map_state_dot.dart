import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

class WorldMapDot extends StatefulWidget {
  final QuestActivityCard card;
  final ActivityPinState state;
  final PinTier tier;
  final VoidCallback onTap;
  final bool pinged;
  final double fill;

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
                  )
                : _SmallDotContent(state: widget.state, fill: widget.fill),
          ),
        ),
      ),
    );
  }
}

class _SmallDotContent extends StatelessWidget {
  final ActivityPinState state;
  final double fill;

  const _SmallDotContent({required this.state, this.fill = 0});

  @override
  Widget build(BuildContext context) => _WorldMapStateDot(
    state: state,
    diameter: 18,
    borderWidth: 1.5,
    fill: fill,
  );
}

class _MediumDotContent extends StatelessWidget {
  final ActivityPinState state;
  final bool pinged;
  final double fill;

  const _MediumDotContent({
    required this.state,
    required this.pinged,
    this.fill = 0,
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

/// The state-coloured pin body with the progress fill: an outer [state]-coloured
/// disc, an inner gold disc whose radius scales with [fill] (0..1 — stars earned
/// toward the activity's total), and an optional [glyph] on top. The fill is
/// linear in radius (`r = innerRadius·fill`), so a full activity reads as a solid
/// gold centre while a fresh one shows none. Design: world-map.instructions.md.
class _WorldMapStateDot extends StatelessWidget {
  final ActivityPinState state;
  final double diameter;
  final double borderWidth;
  final double fill;
  final Widget? glyph;

  const _WorldMapStateDot({
    required this.state,
    required this.diameter,
    required this.borderWidth,
    this.fill = 0,
    this.glyph,
  });

  @override
  Widget build(BuildContext context) {
    final inner = (diameter - 2 * borderWidth) * fill.clamp(0.0, 1.0);
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: state.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: borderWidth),
        boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (inner > 0)
            Container(
              width: inner,
              height: inner,
              decoration: const BoxDecoration(
                color: AppConfig.gold,
                shape: BoxShape.circle,
              ),
            ),
          ?glyph,
        ],
      ),
    );
  }
}
