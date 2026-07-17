import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';

extension OrchestratorClientExtension on Client {
  Set<String> scanCompletedGoalIds({
    required String? activityId,
    required ActivityPlanModel? activity,
    required String roleId,
  }) {
    if (activityId == null) return {};
    final role = activity?.roles[roleId];
    if (role == null) return {};
    final completed = <String>{};
    for (final room in rooms) {
      if (room.activityId != activityId) continue;
      if (room.ownRoleState?.id != roleId) continue;
      final awarded = room.orchestratorAwardedGoals;
      for (final g in role.allGoals) {
        if (awarded.isGoalCompletedForRole(
          roleId,
          g.id,
          goalSlug: g.goalSlug,
        )) {
          completed.add(g.id);
        }
      }
    }
    return completed;
  }

  /// Profile star total: counts saved sessions only. Stars earned in a
  /// session bank into this total when the session is auto-saved on
  /// completion — see activities.instructions.md → "Completion saves itself".
  int totalStarsEarned(LanguageModel lang) {
    final sessions = <SessionStars>[];
    for (final room in rooms) {
      final activityId = room.activityId;
      final activityLang = room.activityPlan?.req.targetLanguage;
      final roleId = room.ownRoleState?.id;
      if (activityId == null || roleId == null || activityLang == null) {
        continue;
      }

      if (lang.langCodeShort != activityLang.split('-').first) continue;

      sessions.add((
        activityId: activityId,
        earned: room.orchestratorAwardedGoals.awards[roleId]?.length ?? 0,
        saved: room.hasArchivedActivity,
      ));
    }
    return totalBankedStars(sessions);
  }
}

typedef SessionStars = ({String activityId, int earned, bool saved});

/// Sums banked stars: saved sessions only, deduped to the best run per
/// activity so replays don't double-count.
@visibleForTesting
int totalBankedStars(Iterable<SessionStars> sessions) {
  final byActivity = <String, int>{};
  for (final session in sessions) {
    if (!session.saved) continue;
    if (session.earned > (byActivity[session.activityId] ?? 0)) {
      byActivity[session.activityId] = session.earned;
    }
  }
  return byActivity.values.fold<int>(0, (a, b) => a + b);
}
