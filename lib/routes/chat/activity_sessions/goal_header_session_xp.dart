import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/quests/course_language_scope.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The XP a live session has earned so far (#9559) — its messages, practice
/// credited to its room, and 100 per goal, awarded every session — beside
/// the goal header's diamonds. A number, not a meter, so the header keeps
/// its eye on the current goal. Rebuilds as XP lands. Nothing for a viewer
/// who holds no role, or in a session whose language isn't the learner's
/// current one: XP is kept per language, so only its goals would count.
class GoalHeaderSessionXp extends StatelessWidget {
  final Room room;

  const GoalHeaderSessionXp({required this.room, super.key});

  /// Whether [room]'s XP is shown to the learner: they hold a role in it,
  /// and it is in their current language. The goals' "+50" labels follow
  /// the same rule, so a session never shows goal XP without its total.
  static bool shows(Room room) =>
      room.ownRole != null && CourseLanguageScope.sessionInTargetLanguage(room);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: MissionXpCache.instance,
    builder: (context, _) {
      if (!shows(room)) return const SizedBox.shrink();
      final sessionXp = room.client.sessionXp(
        room,
        MissionXpCache.instance.creditedXpByRoom,
      );
      final theme = Theme.of(context);
      final l10n = L10n.of(context);
      return Semantics(
        label: l10n.xpAmount(sessionXp),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 3.0,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 14.0,
                // Decorative: the number beside it says it.
                color: theme.pangea.goldGraphic,
              ),
              Text(
                l10n.xpAmount(sessionXp),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
