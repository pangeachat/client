import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// A Mission's target vocabulary: every suggested-vocab entry across the
/// activities that satisfy it in the learner's joined courses, one entry per
/// lemma. What a Mission-scoped practice session draws on (#9438), and the
/// same words whose practice XP the resolver credits to the Mission
/// (quests.instructions.md, "What fills a Mission").
class MissionVocab {
  final LearningObjective objective;
  final List<Vocab> vocab;

  const MissionVocab({required this.objective, required this.vocab});

  Set<String> get lemmas => {for (final v in vocab) v.lemma.toLowerCase()};

  /// Null when no joined course carries [missionId] — a stale link, or a
  /// course since left; the caller falls back to unscoped practice.
  static Future<MissionVocab?> resolve(Client client, String missionId) async {
    for (final room in client.joinedCourseRooms) {
      final questId = room.coursePlan?.uuid;
      if (questId == null) continue;
      final outline = (await QuestRepo.outline(
        questId,
        courseRoomId: room.id,
      )).result;
      if (outline == null) continue;
      for (final group in outline.groups) {
        if (group.objective.id != missionId) continue;
        final byLemma = <String, Vocab>{};
        for (final activity in group.activities) {
          for (final word in activity.plan.vocab) {
            byLemma.putIfAbsent(word.lemma.toLowerCase(), () => word);
          }
        }
        return MissionVocab(
          objective: group.objective,
          vocab: byLemma.values.toList(),
        );
      }
    }
    return null;
  }
}
