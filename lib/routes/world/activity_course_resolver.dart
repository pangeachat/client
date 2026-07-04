import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';

/// Resolves which of the user's joined course spaces an activity belongs
/// to. Used to share new activity sessions into matching course spaces
/// and to scope completion lookups for the world-map popup.
class ActivityCourseResolver {
  /// Joined course spaces the activity is **eligible** for: those whose quest
  /// Learning Objectives intersect the activity's own LO refs, at a matching
  /// target language ([activityL2], region-insensitive, e.g. `es` matches
  /// `es-MX`; null skips the L2 check).
  ///
  /// A direct LO intersection: one thin read for the activity's LO refs, then
  /// one light quest read per joined course — not the full quest outline (which
  /// also fetches every LO-matching activity plan + media and caps at 200).
  /// Same eligibility the map's per-course ranking assumes. See
  /// activities.instructions.md.
  static Future<List<Room>> matchingCourseSpaces(
    Client client,
    String activityId,
    String? activityL2,
  ) async {
    final spaces = client.rooms
        .where(
          (room) =>
              room.isSpace &&
              room.membership == Membership.join &&
              room.coursePlan != null,
        )
        .toList();
    if (spaces.isEmpty) return [];

    final activityRefs = (await QuestRepo.activityLearningObjectiveRefs(
      activityId,
    )).toSet();
    if (activityRefs.isEmpty) return [];

    String short(String code) => code.split('-').first.toLowerCase();

    final matching = <Room>[];
    await Future.wait(
      spaces.map((space) async {
        try {
          final quest = await QuestRepo.quest(space.coursePlan!.uuid);
          if (activityL2 != null &&
              short(quest.targetLanguage) != short(activityL2)) {
            return;
          }
          if (quest.learningObjectiveIds.any(activityRefs.contains)) {
            matching.add(space);
          }
        } catch (_) {
          // A course whose quest can't be resolved simply doesn't match.
        }
      }),
    );
    return matching;
  }
}
