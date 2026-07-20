import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat_list/unread_bubble.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_pinged_badge.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_room_extension.dart';
import 'package:fluffychat/routes/world/world_map_selection.dart';
import 'package:fluffychat/routes/world/world_map_star_dot.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// One participant in a featured joinable/ongoing session — just what the
/// avatar stack needs, decoupled from the Matrix SDK type.
typedef LargeCardParticipant = ({Uri? avatar, String name});

/// Pops [child] (a [WorldMapLargeCard]) in on mount and shrinks it back out on
/// [dying], mirroring [WorldMapDot]'s exact enter/exit contract
/// (`world_map_state_dot.dart`) so a mid-pin's shrink-out and a promoted
/// card's grow-in read as one continuous pop rather than two independently-
/// timed effects. Anchored `Alignment.bottomCenter` to match the marker's own
/// bottom-anchored layout (the card grows up from its pin).
class WorldMapLargeCardAnimated extends StatefulWidget {
  final Widget child;

  /// When true, the card plays its exit animation (scale + fade → 0) then
  /// calls [onExited]. The parent keeps the widget in the tree until
  /// [onExited] fires.
  final bool dying;
  final VoidCallback? onExited;

  const WorldMapLargeCardAnimated({
    super.key,
    required this.child,
    this.dying = false,
    this.onExited,
  });

  @override
  State<WorldMapLargeCardAnimated> createState() =>
      _WorldMapLargeCardAnimatedState();
}

class _WorldMapLargeCardAnimatedState extends State<WorldMapLargeCardAnimated>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 220);

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duration);
    if (!widget.dying) _ctrl.forward();
  }

  @override
  void didUpdateWidget(WorldMapLargeCardAnimated old) {
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
    final curved = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: curved,
        alignment: Alignment.bottomCenter,
        child: widget.child,
      ),
    );
  }
}

/// The large featured map card. Eligible for only two colour-states
/// (world-map.instructions.md, "Pin display"): `joinable` never renders here —
/// `available`/`inProgress`/`completed` are excluded by the ranking/placement
/// hard gate before this widget is ever built, so its body only has real
/// content for `joinable`, `ongoingPending`, and `ongoingActive`.
///
/// - **Joinable** (green border) — title, then a door icon + the participant
///   row (filled/unfilled avatar circles, one per role). No image, stars, or
///   message preview.
/// - **Ongoing/Pending** (dark-purple border) — same layout as Joinable, an
///   hourglass icon in place of the door: the learner holds a role, but the
///   room doesn't yet have enough people for the chat to have started.
/// - **Ongoing/Active** (dark-purple border) — a chat-list tile: title, the
///   last chat event, then the row of currently-gained stars — the only
///   large-card state that shows stars.
///
/// The full [plan] carries the goal total (the hydration fetch localizes;
/// choreo #2736) — null while it hydrates. [liveRoom] is the learner's own
/// session room for an Ongoing card (participants for Pending, last event for
/// Active). Tapping the card opens the activity's plan page.
class WorldMapLargeCard extends StatelessWidget {
  /// Height of the downward caret that tethers the card to its pin. The marker
  /// reserves this beneath the card so the tail isn't clipped (#7153).
  static const double tailHeight = 11.0;
  static const double _tailWidth = 22.0;

  /// How far the unread badge peeks off the card's top-right corner. The
  /// marker box reserves this much slack on the top and both sides (the card
  /// stays bottom-centre-anchored on the pin) so the peeking badge isn't
  /// clipped at the marker bounds.
  static const double badgeOverhang = 8.0;

  final QuestActivityCard card;
  final ActivityPinState state;
  final bool pinged;
  final ActivityPlanModel? plan;
  final Room? liveRoom;
  final int starsEarned;
  final List<LargeCardParticipant> participants;
  final int openSlots;
  final VoidCallback onTap;

  /// The learner's completion tier for this activity. When not `none`, the
  /// completed-activity trail star (or super star) rides BEHIND the card,
  /// peeking below the caret tip exactly like a mid pin — a joinable/ongoing
  /// card stacked on a previously-completed activity keeps its star visible
  /// (world-map.instructions.md, "Goal Progress"). Distinct from the in-session
  /// star row, which shows only during an `ongoingActive` session.
  final ActivityStarLevel starLevel;

  /// When true, the activity is focused (its detail panel is open): the card
  /// darkens its state-accent frame slightly and casts a soft state-coloured
  /// glow around the whole balloon (caret included) — no outline — matching a
  /// selected pin ([WorldMapSelection]), persistent through zoom/pan and cleared
  /// when the panel closes or another activity is focused (#7349). Decoupled
  /// from selection and featuring. See world-map.instructions.md.
  final bool isFocused;

  /// When non-null, the card shows an explicit dismiss (X) that **demotes** the
  /// activity out of the large tier for the session — it re-renders as a mid pin
  /// or dot, never leaving the map (#7207). On a focused card the X also clears
  /// focus (closing the detail panel). Null hides the X (widget-test/reuse knob).
  final VoidCallback? onClose;

  const WorldMapLargeCard({
    super.key,
    required this.card,
    required this.state,
    required this.pinged,
    required this.plan,
    required this.starsEarned,
    required this.onTap,
    this.liveRoom,
    this.isFocused = false,
    this.onClose,
    this.participants = const [],
    this.openSlots = 0,
    this.starLevel = ActivityStarLevel.none,
  });

  /// The activity's star total, never hydration-gated (#7602): the learner's
  /// own role in the live session (real-time, and the same source as the
  /// ongoing row's numerator) → the pin's thin goals (uniform across roles by
  /// generation, min when they disagree — [QuestActivityCard.thinStarsTotal])
  /// → the hydrated plan, a last resort for legacy cards without thin goals.
  int get _starsTotal =>
      liveRoom?.ownRole?.allGoals.length ??
      card.thinStarsTotal ??
      plan?.earnableStars ??
      0;

  @override
  Widget build(BuildContext context) {
    // Selected (focused) treatment: NO outline. The state-accent frame darkens
    // slightly and a soft state-coloured glow haloes the whole balloon — matched
    // to a selected pin ([WorldMapSelection], #7349). The plain accent frame
    // shows when not focused; the glow's downward bleed covers the caret below,
    // so the halo wraps card + tail as one continuous shape.
    final accent = isFocused
        ? WorldMapSelection.darken(state.accent)
        : state.accent;

    final cardButton = GestureDetector(
      onTap: onTap,
      // #Pangea: announce the card as a single "Activity: <title>" button so the
      // screen reader gets context and the title is not double-read (#7185).
      child: Semantics(
        label: L10n.of(context).activityLabel((plan?.title ?? card.title)),
        container: true,
        button: true,
        // The glow rides on the card body's own rounded rect (no gap, no border):
        // the caret directly below sits within its downward bleed, so card and
        // tail glow as one shape (#7349).
        child: DecoratedBox(
          decoration: isFocused
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: WorldMapSelection.glow(state.accent),
                )
              : const BoxDecoration(),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.surface,
            // Cap the width but let the card shrink to its content, so a
            // 2-role pending card doesn't stretch to fill the full width —
            // a little size variety (world-map Figma). The marker box stays
            // the max width and centres the card, so the tail still lands on
            // the pin.
            child: Container(
              constraints: const BoxConstraints(maxWidth: PinSize.largeWidth),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent, width: 4),
              ),
              child: Column(
                spacing: 8.0,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardTitleRow(
                    title: plan?.title ?? card.title,
                    accent: accent,
                    onClose: onClose,
                  ),
                  _CardBody(
                    state: state,
                    accent: accent,
                    liveRoom: liveRoom,
                    participants: participants,
                    openSlots: openSlots,
                    starsTotal: _starsTotal,
                    starsEarned: starsEarned,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // A downward caret tethers the card to its pin: the card floats just above
    // the dot and the tail points back to it. Filled with the accent colour
    // (the same as the card's thick outline) so the card reads as a solid
    // accent-framed balloon pointing at the pin (world-map Figma).
    final cardWithTail = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        cardButton,
        Transform.translate(
          offset: const Offset(0, -1.5),
          child: CustomPaint(
            size: const Size(_tailWidth, tailHeight),
            painter: _CaretPainter(fill: accent, edge: accent),
          ),
        ),
      ],
    );

    // A single TOP-RIGHT badge peeks off the card's corner to draw the eye,
    // mirroring the mid pin: the recruiting hand before the room is ongoing, or
    // the unread bubble once it's ongoingActive — never both (mutually exclusive
    // by state: the hand is gated to `!isOngoing`, the unread bubble needs a live
    // room in the ongoingActive state). Both white-bordered so they stand out
    // from the same-coloured accent frame. The dismiss X lives inline in the
    // title row ([_CardTitleRow]) where it can't overlap the title.
    final Widget? topRightBadge = (pinged && !state.isOngoing)
        ? const WorldMapPingedBadge()
        : (state == ActivityPinState.ongoingActive && liveRoom != null)
        ? UnreadBubble(room: liveRoom!, borderColor: Colors.white)
        : null;

    // The peek is reserved *inside* this Stack: the card is inset by
    // [badgeOverhang] on the top and both sides (symmetric so it stays centred
    // over the pin), and the badge is anchored to the reserved top-right
    // corner. That keeps the whole badge within the Stack's own bounds — it
    // never overflows into an ancestor that might clip it (a marker box, a
    // transform layer), which a negative-offset peek would rely on.
    final Widget cardVisual = topRightBadge == null
        ? cardWithTail
        : Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: badgeOverhang,
                  left: badgeOverhang,
                  right: badgeOverhang,
                ),
                child: cardWithTail,
              ),
              Positioned(top: 0, right: 0, child: topRightBadge),
            ],
          );

    // A completed activity keeps its trail star visible with the live large card
    // stacked on top: the star peeks below the caret tip exactly like a mid pin
    // (shared [CompletionStarBelowTip]; world-map.instructions.md, "Goal
    // Progress"). Only when the learner has earned it — never on the caret alone.
    if (starLevel == ActivityStarLevel.none) return cardVisual;
    return CompletionStarBelowTip(
      superStar: starLevel == ActivityStarLevel.superStar,
      child: cardVisual,
    );
  }
}

/// The large-card title row: the dismiss X inline at the left (so it can never
/// overlap the title — #7207) followed by the bold, [accent]-coloured activity
/// name (world-map.instructions.md, "Pin display", world-map Figma). The X is
/// omitted when [onClose] is null (widget-test / exiting-card reuse).
class _CardTitleRow extends StatelessWidget {
  final String title;
  final Color accent;
  final VoidCallback? onClose;

  const _CardTitleRow({
    required this.title,
    required this.accent,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onClose != null) ...[
          _DismissButton(onPressed: onClose!),
          const SizedBox(width: 2),
        ],
        // Flexible so a long title wraps/ellipsizes within the (capped) card
        // width instead of overflowing the shrink-to-fit row.
        Flexible(
          // #Pangea: the title is already in the card's Semantics label, so
          // exclude the visible text to avoid a double-read (#7185).
          child: ExcludeSemantics(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dispatches to the one content layout that's real for this card's state.
/// `available`/`inProgress` never reach here in production (the ranking/
/// placement large-tier hard gate excludes them before this widget is ever
/// built — world-map.instructions.md, "Pin display") but a defensive empty
/// body keeps the widget well-defined if a test constructs it directly with
/// one of those states.
class _CardBody extends StatelessWidget {
  final ActivityPinState state;
  final Color accent;
  final Room? liveRoom;
  final List<LargeCardParticipant> participants;
  final int openSlots;
  final int starsTotal;
  final int starsEarned;

  const _CardBody({
    required this.state,
    required this.accent,
    required this.liveRoom,
    required this.participants,
    required this.openSlots,
    required this.starsTotal,
    required this.starsEarned,
  });

  @override
  Widget build(BuildContext context) => switch (state) {
    ActivityPinState.joinable => _ParticipantRow(
      icon: Icons.meeting_room,
      accent: accent,
      participants: participants,
      openSlots: openSlots,
    ),
    ActivityPinState.ongoingPending => _ParticipantRow(
      icon: Icons.hourglass_bottom,
      accent: accent,
      participants: liveRoom?.largeCardParticipants ?? participants,
      openSlots: liveRoom?.numRemainingRoles ?? openSlots,
    ),
    ActivityPinState.ongoingActive => _OngoingActiveBody(
      liveRoom: liveRoom,
      starsTotal: starsTotal,
      starsEarned: starsEarned,
    ),
    ActivityPinState.available ||
    ActivityPinState.inProgress => const SizedBox.shrink(),
  };
}

/// The Joinable / Ongoing-Pending body: a leading icon (door vs hourglass)
/// followed by the participant row (filled/unfilled avatar circles, one per
/// role) — world-map.instructions.md, "Pin state".
class _ParticipantRow extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final List<LargeCardParticipant> participants;
  final int openSlots;

  const _ParticipantRow({
    required this.icon,
    required this.accent,
    required this.participants,
    required this.openSlots,
  });

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty && openSlots <= 0) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    // Shrink-wrap so a card with few roles doesn't stretch to the full width —
    // the card sizes to this row (world-map Figma, size variety).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 8),
        for (final p in participants.take(4)) ...[
          Avatar(mxContent: p.avatar, name: p.name, size: 28),
          const SizedBox(width: 4),
        ],
        // An open seat, matching the activity-lobby's open-role look
        // (ActivityParticipantIndicator) — a person-icon avatar on the
        // primary container, scaled to this row's 28px avatars — rather than a
        // bespoke glyph, so the two surfaces read the same.
        for (int i = 0; i < openSlots.clamp(0, 4); i++) ...[
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.person,
              size: 16,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ],
    );
  }
}

/// The Ongoing/Active body: a chat-list tile — the last chat event beneath the
/// title (rendered above by [_CardTitle]), then the row of currently-gained
/// stars at the bottom. **The only large-card state that shows stars**
/// (world-map.instructions.md, "Goal Progress").
class _OngoingActiveBody extends StatelessWidget {
  final Room? liveRoom;
  final int starsTotal;
  final int starsEarned;

  const _OngoingActiveBody({
    required this.liveRoom,
    required this.starsTotal,
    required this.starsEarned,
  });

  @override
  Widget build(BuildContext context) {
    final lastEvent = liveRoom?.lastEvent;
    final sender = lastEvent?.senderFromMemoryOrFallback;
    final preview = lastEvent?.calcLocalizedBodyFallback(
      MatrixLocals(L10n.of(context)),
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
      removeMarkdown: true,
      withSenderNamePrefix: false,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8.0,
      children: [
        if (preview != null)
          Row(
            children: [
              Avatar(
                mxContent: sender?.avatarUrl,
                name: sender?.calcDisplayname(),
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        // Fixed height prevents the card from jumping when `plan` hydrates and
        // the total goes from 0 → actual goal count.
        SizedBox(
          height: 16,
          child: ActivityStarRow(
            total: starsTotal,
            earned: starsEarned.clamp(0, starsTotal),
            condensed: starsTotal > 12,
          ),
        ),
      ],
    );
  }
}

/// The inline dismiss X: a bare close glyph with a circular hover/splash — the
/// app's usual close-button treatment — sized compactly to sit on the title
/// line. Tapping it demotes the card ([WorldMapLargeCard.onClose]); the
/// gesture arena routes the tap here rather than to the card's open-on-tap.
class _DismissButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _DismissButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.close),
      iconSize: 18,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      tooltip: L10n.of(context).close,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

/// A downward speech-bubble tail: a [fill]-filled triangle whose two upper edges
/// are stroked in [edge] (the card's accent border), with the top (base) left
/// open so it merges into the card's bottom border above it.
class _CaretPainter extends CustomPainter {
  final Color fill;
  final Color edge;

  const _CaretPainter({required this.fill, required this.edge});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final triangle = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w / 2, h)
      ..close();
    canvas.drawPath(triangle, Paint()..color = fill);

    // Stroke only the two diagonals; the base connects to the card border above.
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(w / 2, h)
        ..moveTo(w, 0)
        ..lineTo(w / 2, h),
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CaretPainter old) => old.fill != fill || old.edge != edge;
}
