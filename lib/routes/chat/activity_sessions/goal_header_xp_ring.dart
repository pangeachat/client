import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/xp_border_painter.dart';

/// The gold ring around a live session's goal header: it fills with the
/// session's XP toward what the Mission the session serves still needs, the
/// same drawing as the level ring on the world cluster, so a session that
/// completes an objective is visible as it happens (org activities doc,
/// "Activity XP"). No ring when no joined course lists the activity — there
/// is no Mission to fill. Rebuilds as XP lands and as the progression moves.
class GoalHeaderXpRing extends StatelessWidget {
  final Room room;
  final Widget child;

  static const double stroke = 4.0;

  const GoalHeaderXpRing({required this.room, required this.child, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      MissionXpCache.instance,
      QuestObjectivesLoader.sharedProgression,
    ]),
    builder: (context, _) {
      final activityId = room.activityId;
      final mission = activityId == null
          ? null
          : QuestObjectivesLoader.sharedProgression.value.missionForActivity(
              activityId,
            );
      if (mission == null) return child;
      final sessionXp = room.client.sessionXp(
        room,
        MissionXpCache.instance.creditedXpByRoom,
      );
      final remaining = mission.progress.threshold - mission.progress.xp;
      final progress = remaining <= 0
          ? 1.0
          : (sessionXp / remaining).clamp(0.0, 1.0);
      final theme = Theme.of(context);
      return Semantics(
        label: L10n.of(
          context,
        ).sessionXpTowardObjective(sessionXp, remaining < 0 ? 0 : remaining),
        child: CustomPaint(
          painter: XpBorderPainter(
            progress: progress,
            trackColor: XpBorderPainter.trackColorFor(theme),
            progressColor: XpBorderPainter.arcColorFor(theme),
            stroke: stroke,
            innerRadius: AppConfig.borderRadius,
          ),
          child: Padding(
            padding: const EdgeInsets.all(stroke + XpBorderPainter.trackExtra),
            child: child,
          ),
        ),
      );
    },
  );
}
