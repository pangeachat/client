import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// A large map pin drawn as the activity's own card (#9420 prototype, option C,
/// under [kMapActivityCards]): the course plan's [ActivitySuggestionCard] with
/// a squashed photo, its live state as the frame and corner tab, on a tail
/// that points at the activity's location. When the learner has played it,
/// the tail stops short of the point so the card stands on the played stamp
/// — which the map draws on its own layer at the point, so dismissing the
/// card leaves the stamp where it was.
class WorldMapActivityCard extends StatelessWidget {
  final QuestActivityCard card;
  final ActivityPinState state;
  final ActivityPlanModel? plan;
  final int starsEarned;
  final List<String> participants;
  final int openSlots;
  final bool standsOnStamp;
  final bool isFocused;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const WorldMapActivityCard({
    required this.card,
    required this.state,
    required this.plan,
    required this.starsEarned,
    required this.participants,
    required this.openSlots,
    required this.standsOnStamp,
    required this.onTap,
    this.isFocused = false,
    this.onClose,
    super.key,
  });

  /// The marker box this card needs: the card, its tail, the stamp clearance
  /// when it stands on one, and room above for the focus ring.
  static Size boxFor({required bool standsOnStamp}) => Size(
    PinSize.mapCardWidth + 8.0,
    PinSize.mapCardHeight +
        PinSize.mapCardTail +
        (standsOnStamp ? PinSize.mapCardStampClearance : 0) +
        4.0,
  );

  bool get _live =>
      state == ActivityPinState.joinable ||
      state == ActivityPinState.ongoingPending ||
      state == ActivityPinState.ongoingActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final tailColor = _live
        ? state.bodyColor(context)
        : theme.colorScheme.outlineVariant;
    final plan = this.plan;
    final title = plan?.title ?? card.title;

    final body = plan == null
        ? _PlainCard(title: title)
        : ActivitySuggestionCard(
            activity: plan,
            width: PinSize.mapCardWidth,
            height: PinSize.mapCardHeight,
            imageHeight: PinSize.mapCardImageHeight,
            fontSize: 12.0,
            fontSizeSmall: 9.0,
            iconSize: 9.0,
            starsEarned: starsEarned,
            pinState: _live ? state : null,
            participants: participants,
            openSlots: openSlots,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Semantics(
              button: true,
              label: '${l10n.activityLabel(title)}, ${state.label(l10n)}',
              child: Material(
                color: Colors.transparent,
                elevation: 3.0,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(12.0),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12.0),
                  onTap: onTap,
                  child: ExcludeSemantics(child: body),
                ),
              ),
            ),
            if (isFocused)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13.0),
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 2.0,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                    ),
                  ),
                ),
              ),
            if (onClose != null)
              Positioned(
                top: 4.0,
                right: 4.0,
                child: Semantics(
                  button: true,
                  label: l10n.close,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onClose,
                      child: const SizedBox.square(
                        dimension: 22.0,
                        child: Icon(
                          Icons.close_rounded,
                          size: 14.0,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        CustomPaint(
          size: const Size(16.0, PinSize.mapCardTail),
          painter: _TailPainter(color: tailColor),
        ),
        if (standsOnStamp)
          const SizedBox(height: PinSize.mapCardStampClearance),
      ],
    );
  }
}

/// The card before its plan has loaded: the title on the plain card surface.
class _PlainCard extends StatelessWidget {
  final String title;

  const _PlainCard({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: PinSize.mapCardWidth,
      height: PinSize.mapCardHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12.0),
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
