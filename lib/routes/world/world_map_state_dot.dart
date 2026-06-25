import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

class WorldMapDot extends StatelessWidget {
  final QuestActivityCard card;
  final ActivityPinState state;
  final PinTier tier;
  final VoidCallback onTap;
  final bool pinged;
  final double fill;

  const WorldMapDot({
    super.key,
    required this.card,
    required this.state,
    required this.tier,
    required this.onTap,
    required this.pinged,
    this.fill = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: card.title,
      // Semantics below names the pin; exclude the Tooltip so the title isn't
      // announced twice ("<title> <title>").
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: L10n.of(context).activityLabel(card.title),
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: tier == PinTier.mid
              ? _MediumDotContent(state: state, pinged: pinged, fill: fill)
              : _SmallDotContent(state: state, fill: fill),
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
