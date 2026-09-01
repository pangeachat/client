import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/languages/language_flag_chip.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/activity_tile_body.dart';
import 'package:fluffychat/routes/chat_list/unread_bubble.dart';
import 'package:fluffychat/routes/world/activity_participant_row.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_pinged_badge.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_room_extension.dart';
import 'package:fluffychat/routes/world/world_map_selection.dart';
import 'package:fluffychat/routes/world/world_map_star_dot.dart';
import 'package:fluffychat/widgets/avatar.dart';

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

  /// Whether a freshly created state plays the entry grow-in. False for cards
  /// already on screen at the last settle — MarkerLayer's per-frame positional
  /// reconciliation can discard and recreate this State mid-gesture, and such
  /// a card must render at full scale instead of replaying its pop-in (#8136).
  /// Mirrors [WorldMapDot.animateIn].
  final bool animateIn;

  const WorldMapLargeCardAnimated({
    super.key,
    required this.child,
    this.dying = false,
    this.onExited,
    this.animateIn = true,
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
    if (widget.dying) {
      // Built fresh by ExitingLargeMarkersLayer, so didUpdateWidget's
      // false→true arm never runs — play the exit from here or onExited never
      // fires and the card leaks into _exitingLarge (#8136). Mirrors
      // WorldMapDot.
      _ctrl.value = 1.0;
      _ctrl.reverse().then((_) => widget.onExited?.call());
    } else if (widget.animateIn) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1.0;
    }
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

/// The large featured map card. Eligible for four colour-states
/// (world-map.instructions.md, "Pin display"): only the completed trail star
/// (`inProgress`) never renders here — it is a gold-star dot, excluded by the
/// ranking/placement gate before this widget is ever built.
///
/// - **Available** (border maps the mid pin's body colour — light-purple in
///   light mode, the darker `AppConfig.primaryColorDark` purple in dark;
///   dark-purple title) — title, then a row with the L2 language flag, CEFR
///   level, and designed party size (a people icon + the role count). No session
///   exists yet, so no participant avatars, rating, or stars. Dimmed to 50% when
///   [understaffed] (course-scoped).
/// - **Joinable** (green border) — title, then a door icon + the participant
///   row (filled/unfilled avatar circles, one per role). No image, stars, or
///   message preview.
/// - **Ongoing/Pending** (dark-purple border) — same layout as Joinable, an
///   hourglass icon in place of the door: the learner holds a role, but the
///   room doesn't yet have enough people for the chat to have started.
/// - **Ongoing/Active** (dark-purple border) — *is* a chat-list tile, sharing
///   its body widget ([ActivityTileBody]) with the Chats-list tile for the same
///   session: the activity's circular thumbnail leading, and beside it the
///   title over the last chat event (with its sender's avatar) over the row of
///   currently-gained stars — the only large-card state that shows stars, and
///   the only one with an image.
///
/// Every state lays out against a leading gutter ([_LeadingGutter]) so its
/// title sits directly above its content on one left edge, with the dismiss X
/// in that gutter's top corner.
///
/// The full [plan] carries the goal total AND the title in the resolved
/// display language (the hydration fetch localizes; #8397) — null while it
/// hydrates, so the title falls back to the thin [card] title until the plan
/// lands (and re-hydrates on an L1 change, per the map's L1 warmup).
/// [liveRoom] is the learner's own session room for an Ongoing card
/// (participants for Pending, last event for Active). Tapping the card opens
/// the activity's plan page.
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
  final List<String> participants;
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

  /// When true, this `available` card's activity can't currently be staffed by
  /// the course — the whole card renders at 50% opacity, the large-tier mirror
  /// of an understaffed mid pin (world-map.instructions.md, "Understaffed
  /// pins"). Course-scoped only; never set for a live/completed card.
  final bool understaffed;

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
    this.understaffed = false,
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

  /// Inset between the card's border and its content.
  static const double _cardPadding = 10.0;

  /// Leading image size. Smaller than the chat list's [Avatar.defaultSize] 44
  /// because the card is only [PinSize.largeMinWidth]–[PinSize.largeWidth]
  /// wide: at 44 a two-line title had barely half the card left.
  static const double _thumbnailSize = 40.0;

  bool get _hasThumbnail =>
      state == ActivityPinState.ongoingActive && liveRoom != null;

  /// Width of the leading gutter. Holds the thumbnail where there is one; on a
  /// plain card it is blank but still wide enough that the corner X, which
  /// paints over the content rather than taking a slot in a row, clears the
  /// text. Constant whether or not the card has an X, so an exiting card
  /// (which drops its X) doesn't shift its text as it animates out.
  double get _gutterWidth =>
      _hasThumbnail ? _thumbnailSize + 8.0 : _DismissButton.size + 4.0;

  @override
  Widget build(BuildContext context) {
    // The outer frame (border + caret) maps the mid pin's BODY colour, so the
    // card and its pin read as one state. That is theme-aware: for `available`
    // in dark mode it is the darker `AppConfig.primaryColorDark` purple
    // (matching the dark-mode available pin, #8174), not the light-mode
    // light-purple fill. `bodyColor` == the state hue for every other state and
    // for light mode, so only available-in-dark changes here.
    final baseAccent = state.bodyColor(context);

    // Selected (focused) treatment: NO outline. The state-accent frame darkens
    // slightly and a soft state-coloured glow haloes the whole balloon — matched
    // to a selected pin ([WorldMapSelection], #7349). The plain accent frame
    // shows when not focused; the glow's downward bleed covers the caret below,
    // so the halo wraps card + tail as one continuous shape.
    final accent = isFocused
        ? WorldMapSelection.darken(baseAccent)
        : baseAccent;

    // The title (and, on the available card, its body glyphs) use the state's
    // LABEL colour, which differs from the border accent only for `available`:
    // its light-purple fill/border is too low-contrast for a light-purple
    // title on the white card, so the title uses dark purple instead
    // (world-map.instructions.md, "Pin state"). For every live state
    // labelColor == accent, so this is a no-op there.
    final titleColor = isFocused
        ? WorldMapSelection.darken(state.labelColor)
        : state.labelColor;

    final cardButton = Semantics(
      label:
          "${L10n.of(context).activityLabel(plan?.title ?? card.title)}, ${state.label(L10n.of(context))}",
      container: true,
      child: GestureDetector(
        onTap: onTap,
        // The glow rides on the card body's own rounded rect (no gap, no border):
        // the caret directly below sits within its downward bleed, so card and
        // tail glow as one shape (#7349).
        child: DecoratedBox(
          decoration: isFocused
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: WorldMapSelection.glow(baseAccent),
                )
              : const BoxDecoration(),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.surface,
            // Let the card shrink to its content between a floor and the max
            // width, so an available card with a short title (or a 2-role
            // pending one) doesn't stretch to fill the full width — a little
            // size variety (world-map Figma). The marker box stays the max
            // width and centres the card, so the tail still lands on the pin.
            child: Container(
              constraints: const BoxConstraints(
                minWidth: PinSize.largeMinWidth,
                maxWidth: PinSize.largeWidth,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent, width: 4),
              ),
              // The card's inset is carried by the CONTENT so this Stack spans
              // the whole area inside the border, and the X can reach the
              // corner without overhanging it: an overhang would still PAINT
              // under `Clip.none`, but hit-testing stops at the parent's box,
              // leaving most of the button dead to the touch. `passthrough`
              // keeps the content laid out against the container's constraints.
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(_cardPadding),
                    child: _LeadingGutter(
                      width: _gutterWidth,
                      thumbnail: _hasThumbnail
                          ? Avatar(
                              mxContent: liveRoom!.avatar,
                              name: plan?.title ?? card.title,
                              size: _thumbnailSize,
                            )
                          : null,
                      child: Column(
                        spacing: 8.0,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CardTitleRow(
                            title: plan?.title ?? card.title,
                            titleColor: titleColor,
                          ),
                          _CardBody(
                            card: card,
                            state: state,
                            accent: accent,
                            titleColor: titleColor,
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
                  if (onClose != null)
                    Positioned(
                      top: _cardPadding,
                      left: _cardPadding,
                      child: _DismissButton(onPressed: onClose!),
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
    // from the same-coloured accent frame. The dismiss X is the opposite
    // corner's affordance, but rides INSIDE the border rather than peeking.
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
    final Widget content = starLevel == ActivityStarLevel.none
        ? cardVisual
        : CompletionStarBelowTip(
            superStar: starLevel == ActivityStarLevel.superStar,
            child: cardVisual,
          );

    // An understaffed `available` card dims to 50%, matching its mid pin — purely
    // cosmetic, it still taps and opens the plan (world-map.instructions.md,
    // "Understaffed pins").
    return understaffed ? Opacity(opacity: 0.5, child: content) : content;
  }
}

/// The card's leading column — [thumbnail] where the state has one, blank
/// otherwise — with [child] beside it, giving every row one left edge. The
/// thumbnail is the session room's avatar, set from the activity's image when
/// the session launches, so it is the very picture the tile draws and costs no
/// fetch here.
class _LeadingGutter extends StatelessWidget {
  final double width;
  final Widget? thumbnail;
  final Widget child;

  const _LeadingGutter({
    required this.width,
    required this.thumbnail,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      // Min + Flexible, not Expanded: an available card still shrinks to its
      // content rather than stretching to the full width.
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          // Left-aligned so the gutter's spare width falls as the gap before
          // the text; a bare child would take the gutter's tight width.
          child: thumbnail == null
              ? null
              : Align(alignment: Alignment.centerLeft, child: thumbnail),
        ),
        Flexible(child: child),
      ],
    );
  }
}

/// The large-card title row: the bold, [titleColor]ed activity name
/// (world-map.instructions.md, "Pin display", world-map Figma). The dismiss X
/// used to sit inline ahead of it (#7207); it now rides the card's top-left
/// corner as a badge, where it neither crowds the title nor splits the
/// thumbnail off from the text beside it (#8278).
class _CardTitleRow extends StatelessWidget {
  final String title;
  final Color titleColor;

  const _CardTitleRow({required this.title, required this.titleColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                color: titleColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dispatches to the one content layout that's real for this card's state.
/// `inProgress` never reaches here in production (the completed trail star is a
/// gold-star dot, excluded by the ranking/placement gate before this widget is
/// ever built — world-map.instructions.md, "Pin display"), so it renders a
/// defensive empty body if a test constructs it directly.
class _CardBody extends StatelessWidget {
  final QuestActivityCard card;
  final ActivityPinState state;
  final Color accent;
  final Color titleColor;
  final Room? liveRoom;
  final List<String> participants;
  final int openSlots;
  final int starsTotal;
  final int starsEarned;

  const _CardBody({
    required this.card,
    required this.state,
    required this.accent,
    required this.titleColor,
    required this.liveRoom,
    required this.participants,
    required this.openSlots,
    required this.starsTotal,
    required this.starsEarned,
  });

  @override
  Widget build(BuildContext context) => switch (state) {
    ActivityPinState.available => _AvailableBody(
      card: card,
      accent: titleColor,
    ),
    ActivityPinState.joinable => ActivityParticipantRow(
      icon: Icons.meeting_room,
      accent: accent,
      participants: participants,
      openSlots: openSlots,
    ),
    ActivityPinState.ongoingPending => ActivityParticipantRow(
      icon: Icons.hourglass_bottom,
      accent: accent,
      participants: liveRoom?.largeCardParticipantIds ?? participants,
      openSlots: liveRoom?.numRemainingRoles ?? openSlots,
    ),
    ActivityPinState.ongoingActive => ActivityTileBody(
      room: liveRoom,
      starsTotal: starsTotal,
      starsEarned: starsEarned,
    ),
    ActivityPinState.inProgress => const SizedBox.shrink(),
  };
}

/// The Available body (world-map.instructions.md, "Pin display"): the activity's
/// L2 language flag, its CEFR level, and its designed party size — a people
/// glyph and the role count. No session exists yet, so there is no participant
/// row, rating, or star row; the [card]'s thin metadata (`l2`, `cefr`,
/// `roleCount`) carries everything shown, so this needs no plan hydration.
/// [accent] is the card's dark title colour.
class _AvailableBody extends StatelessWidget {
  final QuestActivityCard card;
  final Color accent;

  const _AvailableBody({required this.card, required this.accent});

  @override
  Widget build(BuildContext context) {
    final roleCount = card.roleCount;
    final langShort = card.l2.split('-').first;
    final cefr = card.cefr;
    return Row(
      // Shrink to the info row's own width (like the joinable participant row)
      // so the card doesn't stretch to the full max width — see the card's
      // width constraints.
      mainAxisSize: MainAxisSize.min,
      children: [
        LanguageFlagChip(
          language: PLanguageStore.byLangCode(langShort),
          langCode: card.l2,
          width: 28,
          height: 20,
          fontSize: 11,
          radius: 4,
          borderWidth: 1.5,
          alwaysShowCode: false,
        ),
        if (cefr != null && cefr.isNotEmpty) ...[
          const SizedBox(width: 12),
          Text(
            cefr.toUpperCase(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
        if (roleCount != null) ...[
          const SizedBox(width: 12),
          Icon(Icons.groups, size: 20, color: accent),
          const SizedBox(width: 4),
          Text(
            '$roleCount',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ],
    );
  }
}

/// The dismiss X, as a corner badge: a close glyph on a surface-coloured disc
/// with the same white ring the top-right badges wear, so it reads against both
/// the card's accent border and the map behind it. Sized to sit in the border's
/// corner curve. Tapping it demotes the card
/// ([WorldMapLargeCard.onClose]); it sits ABOVE the card's content in the
/// stack, and the gesture arena routes its tap here rather than to the card's
/// open-on-tap beneath.
class _DismissButton extends StatelessWidget {
  /// Diameter — small enough to nestle in the card's 12px corner radius, big
  /// enough to be a real tap target on a touch screen.
  static const double size = 30.0;

  final VoidCallback onPressed;

  const _DismissButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Pointer-only: the card draws inside the ExcludeSemantics'd map subtree,
    // which hides this button from assistive tech but NOT from Tab traversal —
    // leaving it in makes an invisible dead Tab stop per visible card (2.4.7).
    // The keyboard path to pins is the mirror layer's single roving stop
    // (#8714, world-map.instructions.md → Keyboard access).
    return ExcludeFocus(
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.close),
        iconSize: 18,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: size, minHeight: size),
        tooltip: L10n.of(context).close,
        color: theme.colorScheme.onSurfaceVariant,
        style: IconButton.styleFrom(
          // Without this the button's box is the 48px padded tap target, not the
          // disc — it would overhang the gutter and swallow taps on the content
          // it paints over.
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: theme.colorScheme.surface,
          shape: const CircleBorder(
            side: BorderSide(color: Colors.white, width: 1.5),
          ),
        ),
      ),
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
