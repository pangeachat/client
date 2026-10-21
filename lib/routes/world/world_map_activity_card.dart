import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/world/world_map_card_dismiss_button.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_selection.dart';

/// A large map pin drawn as the activity's own card (under
/// [kMapActivityCards]): the course plan's [ActivitySuggestionCard] with a
/// squashed photo, its live state as the frame and the pill on its photo, on a
/// tail that points at the activity's location. When the learner has a saved
/// session of it, the card wears the completed stamp with their XP under its
/// name, the same badge in the same place as on the course page's cards
/// (#9559).
///
/// Pointer-only, like the classic large card: the map is excluded from
/// semantics, and its pins are reached by keyboard and screen reader through
/// the pin semantics layer's single roving stop, so the card claims no focus
/// of its own.
class WorldMapActivityCard extends StatelessWidget {
  final QuestActivityCard card;
  final ActivityPinState state;
  final ActivityPlanModel? plan;
  final List<String> participants;
  final int openSlots;

  /// The learner has a saved session of this activity.
  final bool played;

  /// Their total XP from it, for the coin on a [played] card's photo.
  final int xpEarned;

  /// A coursemate pinged the course to fill its open session.
  final bool pinged;
  final bool isFocused;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const WorldMapActivityCard({
    required this.card,
    required this.state,
    required this.plan,
    required this.participants,
    required this.openSlots,
    required this.played,
    this.xpEarned = 0,
    this.pinged = false,
    required this.onTap,
    this.isFocused = false,
    this.onClose,
    super.key,
  });

  bool get _live =>
      state == ActivityPinState.joinable ||
      state == ActivityPinState.ongoingPending ||
      state == ActivityPinState.ongoingActive;

  @override
  Widget build(BuildContext context) {
    // The pointer continues the card's frame (#9559): the live state's hue,
    // else the not-started pin's colour a resting map card is outlined in —
    // the same colour as the mid pin or dot it stands for.
    final frameColor = _live
        ? state.bodyColor(context)
        : ActivityPinState.available.bodyColor(context);
    // Focused, the card takes the selected look it shares with the pins
    // ([WorldMapSelection]): no outline — the frame and pointer darken
    // slightly and the card glows in its frame's colour.
    final tailColor = isFocused
        ? WorldMapSelection.darken(frameColor)
        : frameColor;
    final plan = this.plan;
    final title = plan?.title ?? card.title;

    final body = plan == null
        ? _PlainCard(title: title, live: _live, selected: isFocused)
        : ActivitySuggestionCard(
            activity: plan,
            width: PinSize.mapCardWidth,
            height: PinSize.mapCardHeight,
            imageHeight: PinSize.mapCardImageHeight,
            fontSize: 12.0,
            fontSizeSmall: 9.0,
            iconSize: 9.0,
            pinState: _live ? state : null,
            participants: participants,
            openSlots: openSlots,
            pinged: pinged && _live,
            frameWhenResting: true,
            selected: isFocused,
            timesCompleted: played ? 1 : 0,
            xpEarned: played ? xpEarned : 0,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              // The hover region is exactly the tap region.
              hitTestBehavior: HitTestBehavior.deferToChild,
              child: GestureDetector(
                onTap: onTap,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(PinSize.mapCardRadius),
                    boxShadow: isFocused
                        ? WorldMapSelection.glow(frameColor)
                        : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    elevation: 3.0,
                    shadowColor: Colors.black54,
                    borderRadius: BorderRadius.circular(PinSize.mapCardRadius),
                    child: body,
                  ),
                ),
              ),
            ),
            if (onClose case final onClose?)
              Positioned(
                top: 4.0,
                right: 4.0,
                child: WorldMapCardDismissButton(onPressed: onClose),
              ),
          ],
        ),
        CustomPaint(
          size: const Size(16.0, PinSize.mapCardTail),
          painter: _TailPainter(color: tailColor),
        ),
      ],
    );
  }
}

/// The card before its plan has loaded: the title on the plain card surface.
class _PlainCard extends StatelessWidget {
  final String title;

  /// A resting card wears the not-started outline, as the card that
  /// replaces it will.
  final bool live;

  /// Focused: the outline darkens, as the loaded card's frame does.
  final bool selected;

  const _PlainCard({
    required this.title,
    required this.live,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: PinSize.mapCardWidth,
      height: PinSize.mapCardHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(PinSize.mapCardRadius),
        border: live
            ? null
            : Border.all(
                color: selected
                    ? WorldMapSelection.darken(
                        ActivityPinState.available.bodyColor(context),
                      )
                    : ActivityPinState.available.bodyColor(context),
                width: 2.0,
              ),
      ),
      padding: const EdgeInsets.all(8.0),
      alignment: Alignment.bottomLeft,
      child: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge,
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  final Color color;

  _TailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TailPainter old) => old.color != color;
}
