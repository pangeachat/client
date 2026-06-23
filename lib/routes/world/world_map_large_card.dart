import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// One participant in a featured joinable session — just what the avatar stack
/// needs, decoupled from the Matrix SDK type.
typedef LargeCardParticipant = ({Uri? avatar, String name});

/// The large featured map card (Figma `… Large`). One layout, four state skins:
/// **unlocked** (purple, star progress), **joinable** (green, + participant
/// avatars and open slots), **locked** (gray, lock + unlock-requirement line),
/// and **completed** (full star row + a Completed marker and Play-again /
/// Review). Completion is a fill, not a state — a completed card is an unlocked
/// one whose [starsEarned] has reached the total — so it keeps the unlocked
/// color (see world-map.instructions.md). The full [plan] carries the image and
/// goal total and is null while it hydrates, so the card degrades to a skeleton
/// until it lands. Tapping the card opens the activity's plan page; the map owns
/// that ([onTap]).
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
  bool get _completed =>
      state == ActivityPinState.unlocked &&
      _starsTotal > 0 &&
      starsEarned >= _starsTotal;

  @override
  Widget build(BuildContext context) {
    final joinable = state == ActivityPinState.joinable;
    final locked = state == ActivityPinState.locked;
    final completed = _completed;
    return GestureDetector(
      onTap: onTap,
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
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context, locked: locked, completed: completed),
              // A locked activity has no progress, so no star row — and dropping
              // it keeps the card from overflowing when the requirement wraps.
              if (!locked) ...[const SizedBox(height: 8), _starRow()],
              if (locked) ...[
                const SizedBox(height: 8),
                _lockedRequirement(context),
              ],
              if (completed) ...[
                const SizedBox(height: 8),
                _completedActions(context),
              ],
              if (joinable && (participants.isNotEmpty || openSlots > 0)) ...[
                const SizedBox(height: 8),
                _participantRow(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required bool locked,
    required bool completed,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _thumbnail(locked: locked),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: locked ? AppConfig.grayText : null,
                ),
              ),
              const SizedBox(height: 4),
              _typeChip(context, locked: locked, completed: completed),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _flag(),
      ],
    );
  }

  Widget _thumbnail({bool locked = false}) {
    final url = plan?.imageURL;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: url != null
            ? Image.network(
                url.toString(),
                fit: BoxFit.cover,
                errorBuilder: (context, _, _) => _thumbPlaceholder(),
              )
            : _thumbPlaceholder(),
      ),
    );
    if (!locked) return image;
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: 0.5, child: image),
        const Icon(Icons.lock, size: 20, color: AppConfig.grayText),
      ],
    );
  }

  Widget _thumbPlaceholder() => Container(color: Colors.black12);

  // All v3 activities are conversations today; surfaced as the type chip, unless
  // the activity is completed (a Completed marker takes the chip's place).
  // TODO(world-map): read the real activity type once modeled.
  Widget _typeChip(
    BuildContext context, {
    required bool locked,
    required bool completed,
  }) {
    final l10n = L10n.of(context);
    final Color fg = completed
        ? AppConfig.completedGreen
        : (locked ? AppConfig.grayText : state.accent);
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

  Widget _flag() {
    final lang = PLanguageStore.byLangCode(card.l2);
    final fallback = Text(
      card.l2.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
    );
    if (lang == null || !lang.shouldShowFlag) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SvgPicture.network(
        lang.svgUrl.toString(),
        width: 28,
        height: 20,
        fit: BoxFit.cover,
        errorBuilder: (context, _, _) => fallback,
        placeholderBuilder: (_) => const SizedBox(width: 28, height: 20),
      ),
    );
  }

  Widget _starRow() {
    final total = _starsTotal;
    // Plan still hydrating (or no goals): leave the row's height so the card
    // doesn't jump when the stars land.
    if (total == 0) return const SizedBox(height: 16);
    final earned = starsEarned.clamp(0, total);
    final shown = total > 12 ? 12 : total;
    return Row(
      children: [
        for (var i = 0; i < shown; i++)
          Icon(
            i < earned ? Icons.star : Icons.star_border,
            size: 16,
            color: i < earned ? AppConfig.gold : Colors.black26,
          ),
      ],
    );
  }

  // The activity behind a locked pin can't be started yet; its plan page opens
  // read-only. The card states why.
  // TODO(world-map): name the specific gating objective + star threshold.
  Widget _lockedRequirement(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.lock, size: 13, color: AppConfig.grayText),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            L10n.of(context).lockedMissionRequirement,
            style: const TextStyle(fontSize: 11, color: AppConfig.grayText),
          ),
        ),
      ],
    );
  }

  // Indicators of what the plan page offers a finished activity; the card itself
  // taps through to that page (it does not act on these inline).
  Widget _completedActions(BuildContext context) {
    final l10n = L10n.of(context);
    return Row(
      children: [
        _actionPill(
          Icons.refresh,
          l10n.playAgain,
          AppConfig.purple,
          const Color(0xFFCECBF6),
        ),
        const SizedBox(width: 6),
        _actionPill(
          Icons.visibility_outlined,
          l10n.reviewActivity,
          AppConfig.grayText,
          const Color(0xFFD3D1C7),
        ),
      ],
    );
  }

  Widget _actionPill(IconData icon, String label, Color fg, Color border) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _participantRow() {
    return Row(
      children: [
        for (final p in participants.take(4)) ...[
          Avatar(mxContent: p.avatar, name: p.name, size: 28),
          const SizedBox(width: 4),
        ],
        for (var i = 0; i < openSlots.clamp(0, 4); i++) ...[
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
    );
  }
}
