import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// One participant in a featured joinable session — just what the avatar stack
/// needs, decoupled from the Matrix SDK type.
typedef LargeCardParticipant = ({Uri? avatar, String name});

/// The large featured map card.
/// **unlocked** (purple, star progress)
/// **joinable** (green, + participant avatars and open slots)
/// **completed** (full star row + a Completed marker and Play-again / Review).
///
/// The full [plan] carries the image and goal total - null while it hydrates
/// Tapping the card opens the activity's plan page.
class WorldMapLargeCard extends StatelessWidget {
  final QuestActivityCard card;
  final ActivityPinState state;
  final bool pinged;
  final ActivityPlanModel? plan;
  final int starsEarned;
  final List<LargeCardParticipant> participants;
  final int openSlots;
  final VoidCallback onTap;

  const WorldMapLargeCard({
    super.key,
    required this.card,
    required this.state,
    required this.pinged,
    required this.plan,
    required this.starsEarned,
    required this.onTap,
    this.participants = const [],
    this.openSlots = 0,
  });

  /// The most-goal role's goal count stands in for the activity's star total: a
  /// learner plays one role, and the richest role bounds the progress bar.
  int get _starsTotal {
    final plan = this.plan;
    if (plan == null) return 0;
    return plan.roles.values
        .map((r) => r.allGoals.length)
        .fold(0, (a, b) => b > a ? b : a);
  }

  /// Completion is a full star row on an unlocked pin (not a separate state). A
  /// pin with a live session reads joinable, not completed, so the learner is
  /// pulled back to play.
  bool get _completed {
    if (state != ActivityPinState.unlocked) return false;
    final starsTotal = _starsTotal;
    return starsTotal > 0 && starsEarned >= starsTotal;
  }

  bool get _showParticipants =>
      state == ActivityPinState.joinable &&
      (participants.isNotEmpty || openSlots > 0);

  @override
  Widget build(BuildContext context) {
    final completed = _completed;
    final total = _starsTotal;

    final earned = starsEarned.clamp(0, total);
    final shown = total > 12 ? 12 : total;

    return GestureDetector(
      onTap: onTap,
      // #Pangea: announce the card as a single "Activity: <title>" button so the
      // screen reader gets context and the title is not double-read (#7185).
      child: Semantics(
        label: L10n.of(context).activityLabel(card.title),
        button: true,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surface,
          child: Container(
            width: 260,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: state.accent, width: 2),
            ),
            child: Column(
              spacing: 8.0,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(
                  card: card,
                  plan: plan,
                  completed: completed,
                  pinged: pinged,
                  foregroundColor: state.accent,
                ),
                ActivityStarRow(
                  total: _starsTotal,
                  earned: earned,
                  condensed: _starsTotal > 12,
                ),
                if (completed)
                  Row(
                    children: [
                      _ActionPill(
                        icon: Icons.refresh,
                        label: L10n.of(context).playAgain,
                        foregroundColor: AppConfig.purple,
                        borderColor: const Color(0xFFCECBF6),
                      ),
                      const SizedBox(width: 6),
                      _ActionPill(
                        icon: Icons.visibility_outlined,
                        label: L10n.of(context).reviewActivity,
                        foregroundColor: AppConfig.grayText,
                        borderColor: const Color(0xFFD3D1C7),
                      ),
                    ],
                  ),
                if (_showParticipants)
                  Row(
                    children: [
                      for (final p in participants.take(4)) ...[
                        Avatar(mxContent: p.avatar, name: p.name, size: 28),
                        const SizedBox(width: 4),
                      ],
                      for (int i = 0; i < openSlots.clamp(0, 4); i++) ...[
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black12,
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black45,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final QuestActivityCard card;
  final ActivityPlanModel? plan;

  final bool completed;
  final bool pinged;
  final Color foregroundColor;

  const _Header({
    required this.card,
    required this.plan,
    required this.completed,
    required this.pinged,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final lang = PLanguageStore.byLangCode(card.l2);

    final flagFallback = Text(
      card.l2.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
    );

    final imageUrl = plan?.imageURL;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 48,
            child: imageUrl != null
                ? Image.network(
                    imageUrl.toString(),
                    fit: BoxFit.cover,
                    semanticLabel: L10n.of(context).activityPhoto,
                    errorBuilder: (context, _, _) =>
                        Container(color: Colors.black12),
                  )
                : Container(color: Colors.black12),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // #Pangea: the title is already in the card's Semantics label, so
              // exclude the visible text to avoid a double-read (#7185).
              ExcludeSemantics(
                child: Text(
                  card.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _TypeChip(
                completed: completed,
                pinged: pinged,
                foregroundColor: foregroundColor,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        lang == null || !lang.shouldShowFlag
            ? flagFallback
            : ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SvgPicture.network(
                  lang.svgUrl.toString(),
                  width: 28,
                  height: 20,
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, _) => flagFallback,
                  placeholderBuilder: (_) =>
                      const SizedBox(width: 28, height: 20),
                ),
              ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final bool completed;
  final bool pinged;
  final Color foregroundColor;

  const _TypeChip({
    required this.completed,
    required this.pinged,
    required this.foregroundColor,
  });

  // All v3 activities are conversations today; surfaced as the type chip, unless
  // the activity is completed (a Completed marker takes the chip's place).
  // TODO(world-map): read the real activity type once modeled.
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    final Color fg = completed ? AppConfig.completedGreen : foregroundColor;

    final IconData icon = completed
        ? Icons.check_circle_outline
        : (pinged ? Icons.back_hand : Icons.chat_bubble_outline);

    final String label = completed
        ? l10n.mapFilterCompleted
        : l10n.activityTypeConversation;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foregroundColor;
  final Color borderColor;

  const _ActionPill({
    required this.icon,
    required this.label,
    required this.foregroundColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foregroundColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}
