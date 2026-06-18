import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';

/// Resolves which of the user's joined course spaces an activity belongs
/// to. Used to share new activity sessions into matching course spaces
/// and to scope completion lookups for the world-map popup.
class ActivityCourseResolver {
  /// Joined course spaces whose v3 quest outline includes [activityId] and
  /// whose target language matches [activityL2] (region-insensitive,
  /// e.g. `es` matches `es-MX`). Null [activityL2] skips the L2 check.
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

    String short(String code) => code.split('-').first.toLowerCase();

    final matching = <Room>[];
    await Future.wait(
      spaces.map((space) async {
        try {
          final outline = await QuestRepo.outline(space.coursePlan!.uuid);
          if (activityL2 != null &&
              short(outline.quest.targetLanguage) != short(activityL2)) {
            return;
          }
          final contains = outline.groups.any(
            (g) => g.activities.any((a) => a.activityId == activityId),
          );
          if (contains) matching.add(space);
        } catch (_) {
          // A course whose quest can't be resolved simply doesn't match.
        }
      }),
    );
    return matching;
  }
}
