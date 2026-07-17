import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat_list/unread_bubble.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_pinged_badge.dart';
import 'package:fluffychat/routes/world/world_map_pin_shape.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_selection.dart';

class WorldMapDot extends StatefulWidget {
  final QuestActivityCard card;
  final ActivityPinState state;
  final PinTier tier;
  final VoidCallback onTap;
  final bool pinged;

  /// The learner's completion tier, used only by the `inProgress` (trail) state
  /// to draw a plain star vs a super star (world-map.instructions.md, "Goal
  /// Progress"). `none` for every other state.
  final ActivityStarLevel starLevel;

  /// The learner's own live room for this activity, when it has unread
  /// messages — only meaningful (and only ever shown) for
  /// [ActivityPinState.ongoingActive] (world-map.instructions.md, "Pin
  /// state"). Null hides the badge.
  final Room? unreadRoom;

  /// Participants filled / total roles, for the mid-pin "num/num" label
  /// (joinable / ongoing-pending only — world-map.instructions.md,
  /// "Pin display"). Null hides the label (e.g. counts not yet resolved).
  final int? participantsFilled;
  final int? participantsTotal;

  /// When true, the activity is focused (its detail panel is open): the dot
  /// darkens its state-coloured body slightly and casts a soft state-coloured
  /// glow — no outline — matching a selected large card ([WorldMapSelection]),
  /// persistent through zoom/pan and cleared when the panel closes or another
  /// activity is focused (#7349). Decoupled from the colour state and star tier.
  /// See world-map.instructions.md.
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
    this.starLevel = ActivityStarLevel.none,
    this.unreadRoom,
    this.participantsFilled,
    this.participantsTotal,
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
          // excludeSemantics drops the DESCENDANT tree — including the
          // GestureDetector's implicit tap action — so this node must carry
          // its own onTap, or assistive tech can name the pin but never
          // activate it (#7591).
          onTap: widget.dying ? null : widget.onTap,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: widget.dying ? null : widget.onTap,
            child: _withCompletionStar(
              widget.tier == PinTier.mid
                  ? _MediumDotContent(
                      state: widget.state,
                      pinged: widget.pinged,
                      unreadRoom: widget.unreadRoom,
                      participantsFilled: widget.participantsFilled,
                      participantsTotal: widget.participantsTotal,
                      starLevel: widget.starLevel,
                      isFocused: widget.isFocused,
                    )
                  : _SmallDotContent(
                      state: widget.state,
                      starLevel: widget.starLevel,
                      isFocused: widget.isFocused,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// A completed activity keeps its star visible even when a NEW session turns
  /// the pin joinable/ongoing: the live pin sits on top and the gold star (or
  /// super star) rides BEHIND it, so the learner still sees they've done this one
  /// before (world-map.instructions.md, "Goal Progress"). Non-interactive — the
  /// live pin owns the tap. Pass-through when there's nothing to show behind:
  /// `inProgress` already renders AS the star, and `available` never carries
  /// completion (it becomes `inProgress` the moment a role is done).
  Widget _withCompletionStar(Widget pin) {
    final state = widget.state;
    if (widget.starLevel == ActivityStarLevel.none ||
        state == ActivityPinState.inProgress ||
        state == ActivityPinState.available) {
      return pin;
    }
    final star = IgnorePointer(
      child: _StarDot(
        superStar: widget.starLevel == ActivityStarLevel.superStar,
      ),
    );
    // A mid teardrop head (44) fully hides a centred star, so push it straight
    // down: horizontally centred on the pin, peeking out from directly beneath
    // the teardrop's tip. A small dot (8) is smaller than the star, so the dot
    // just sits centred on top of it.
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        widget.tier == PinTier.mid
            ? Transform.translate(offset: const Offset(0, 30), child: star)
            : star,
        pin,
      ],
    );
  }
}

class _SmallDotContent extends StatelessWidget {
  final ActivityPinState state;
  final ActivityStarLevel starLevel;
  final bool isFocused;

  const _SmallDotContent({
    required this.state,
    this.starLevel = ActivityStarLevel.none,
    this.isFocused = false,
  });

  @override
  Widget build(BuildContext context) => _WorldMapStateDot(
    state: state,
    diameter: PinSize.smallDiameter,
    borderWidth: 1.0,
    starLevel: starLevel,
    isFocused: isFocused,
  );
}

/// The mid-pin glyph, matching its large-card counterpart icon-for-icon
/// (world-map.instructions.md, "Pin display"): `available` a plus, `joinable`
/// a door, `ongoingPending` an hourglass, `ongoingActive` a chat bubble.
/// `inProgress` renders no glyph — its body is a gold star, not a coloured pin.
IconData? _mediumGlyph(ActivityPinState state) => switch (state) {
  ActivityPinState.available => Icons.add,
  ActivityPinState.joinable => Icons.meeting_room,
  ActivityPinState.ongoingPending => Icons.hourglass_bottom,
  ActivityPinState.ongoingActive => Icons.chat_bubble_outline,
  ActivityPinState.inProgress => null,
};

/// The mid-pin "num/num" participant-count label — `joinable`/`ongoingPending`
/// only (never `ongoingActive`, which shows no count — world-map.instructions.md,
/// "Pin display"). Null when the counts aren't available.
String? _participantLabel(ActivityPinState state, int? filled, int? total) {
  if (state != ActivityPinState.joinable &&
      state != ActivityPinState.ongoingPending) {
    return null;
  }
  if (filled == null || total == null) return null;
  return '$filled/$total';
}

class _MediumDotContent extends StatelessWidget {
  final ActivityPinState state;
  final bool pinged;
  final Room? unreadRoom;
  final int? participantsFilled;
  final int? participantsTotal;
  final ActivityStarLevel starLevel;
  final bool isFocused;

  const _MediumDotContent({
    required this.state,
    required this.pinged,
    this.unreadRoom,
    this.participantsFilled,
    this.participantsTotal,
    this.starLevel = ActivityStarLevel.none,
    this.isFocused = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = _participantLabel(
      state,
      participantsFilled,
      participantsTotal,
    );

    // The icon and (for joinable/ongoing-pending) the "num/num" count stack
    // together as a single glyph inside the circular head, rather than the
    // count sitting in its own reserved row below the pin — so the pin reads
    // as one compact marker (world-map Figma).
    final glyph = switch (_mediumGlyph(state)) {
      null => null,
      final icon => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          if (label != null)
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
        ],
      ),
    };

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        _WorldMapStateDot(
          state: state,
          diameter: PinSize.midDiameter,
          pointHeight: PinSize.midPointHeight,
          borderWidth: 2,
          starLevel: starLevel,
          isFocused: isFocused,
          glyph: glyph,
        ),
        // A single TOP-RIGHT badge: the recruiting hand before the room is
        // ongoing, or the unread bubble once it's ongoingActive — never both
        // (mutually exclusive by state: the hand is gated to `!isOngoing` and
        // `unreadRoom` is only set for ongoingActive). Both white-bordered so
        // they stand out from the pin behind (world-map.instructions.md,
        // "Pin state").
        if (pinged && !state.isOngoing)
          const Positioned(top: -2, right: -2, child: WorldMapPingedBadge())
        else if (unreadRoom != null)
          Positioned(
            top: -2,
            right: -2,
            child: UnreadBubble(room: unreadRoom!, borderColor: Colors.white),
          ),
      ],
    );
  }
}

/// The completed-activity trail marker: a gold [Icons.star] (one role done) or a
/// slightly larger [Icons.hotel_class] **super** star (all roles) centred in a
/// base-colour circle, so the dot reads as a callout on the map rather than a
/// bare glyph (world-map.instructions.md, "Pin state" / "Goal Progress").
class _StarDot extends StatelessWidget {
  final bool superStar;

  const _StarDot({required this.superStar});

  /// The circle diameter for a [superStar] / regular star — also what the
  /// marker-box math and focus ring size to (the super star is the larger).
  static double diameterFor(bool superStar) =>
      superStar ? PinSize.superStarDotDiameter : PinSize.starDotDiameter;

  @override
  Widget build(BuildContext context) => Container(
    width: diameterFor(superStar),
    height: diameterFor(superStar),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      shape: BoxShape.circle,
      boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
    ),
    child: Icon(
      superStar ? Icons.hotel_class : Icons.star,
      size: superStar ? PinSize.superStarGlyphSize : PinSize.starGlyphSize,
      color: AppConfig.gold,
    ),
  );
}

/// The pin body, keyed off the colour [state]:
///
///  - **inProgress** renders as a completed-activity **star dot** (the state
///    _is_ the progress): a gold star (one role done) or a shine super star
///    (all roles — [starLevel]) in a base-colour circle, in place of the
///    coloured body. Binary, never a partial fraction — a pin shows no progress
///    until a full role is complete (world-map.instructions.md, "Goal
///    Progress");
///  - every other state renders as a [state]-coloured body with a white border
///    and an optional [glyph] centered on its circular head. When
///    [pointHeight] is 0 the body is a plain circle (small tier); otherwise a
///    teardrop/map-marker silhouette whose point extends [pointHeight] below
///    the head (mid tier — world-map.instructions.md, "Pin display", the
///    Figma `Activity pin v3` reference).
///
/// When [isFocused], a primary-coloured focus ring (a halo with a gap) wraps
/// the head, distinct from the white state-border (#7349). Progress is shown
/// on the dot only via the inProgress state; a joinable/ongoing pin that also
/// has stars shows the live colour here and its star row on the large card.
/// Design: world-map.instructions.md ("Goal Progress").
class _WorldMapStateDot extends StatelessWidget {
  final ActivityPinState state;
  final double diameter;
  final double borderWidth;
  final ActivityStarLevel starLevel;
  final bool isFocused;
  final Widget? glyph;
  final double pointHeight;

  const _WorldMapStateDot({
    required this.state,
    required this.diameter,
    required this.borderWidth,
    this.starLevel = ActivityStarLevel.none,
    this.isFocused = false,
    this.glyph,
    this.pointHeight = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (state == ActivityPinState.inProgress) {
      // Progress is the state: a fixed-size star dot replaces the coloured body
      // — a super star (all roles) or a plain star (one role). No shape/point.
      final superStar = starLevel == ActivityStarLevel.superStar;
      final star = _StarDot(superStar: superStar);
      return _withSelectedGlow(context, star, _StarDot.diameterFor(superStar));
    }

    if (pointHeight <= 0) {
      // Plain circle (small tier).
      final dot = Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          color: _bodyColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: borderWidth),
          boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
        ),
        child: glyph == null ? null : Center(child: glyph),
      );
      return _withSelectedGlow(context, dot, diameter);
    }

    // Teardrop (mid tier): a CustomPaint sized to the full box (head + point),
    // with the glyph centered over the head only.
    final box = SizedBox(
      width: diameter,
      height: diameter + pointHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: Size(diameter, diameter + pointHeight),
            painter: TeardropPainter(
              color: _bodyColor,
              headDiameter: diameter,
              pointHeight: pointHeight,
            ),
          ),
          if (glyph != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: diameter,
              child: Center(child: glyph),
            ),
        ],
      ),
    );
    return _withSelectedGlow(context, box, diameter, isTeardrop: true);
  }

  /// The pin body's fill, darkened slightly while [isFocused] for the selected
  /// look (the star dot keeps its own gold — only coloured bodies darken).
  Color get _bodyColor =>
      isFocused ? WorldMapSelection.darken(state.color) : state.color;

  /// The selected (focused) treatment: NO outline — a soft state-coloured glow
  /// haloes the pin head (the body itself darkens via [_bodyColor]), so a
  /// selected pin reads the same as a selected large card and at every tier
  /// (#7349, [WorldMapSelection]). Drawn with a Stack + Clip.none so the halo
  /// can bleed past the fixed marker bounds. For a teardrop body the glow haloes
  /// only the circular head (sized to [headDiameter]), pinned at the top of the
  /// point-including box — not the whole taller bounding box.
  Widget _withSelectedGlow(
    BuildContext context,
    Widget dot,
    double headDiameter, {
    bool isTeardrop = false,
  }) {
    if (!isFocused) return dot;

    final glow = Container(
      width: headDiameter,
      height: headDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: WorldMapSelection.glow(state.color),
      ),
    );

    // Glow first so it sits BEHIND the opaque dot — only the blurred halo shows.
    if (!isTeardrop) {
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [glow, dot],
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(top: 0, left: 0, child: glow),
        dot,
      ],
    );
  }
}
