import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// Resolves which of the user's joined course spaces an activity belongs
/// to. Used to share new activity sessions into matching course spaces
/// and to scope completion lookups for the world-map popup.
/// The eligible course matches for an activity, plus whether the match
/// computation was COMPLETE — i.e. every joined course's eligibility was
/// actually determined. A course whose quest can't be resolved (network/parse
/// failure) leaves [complete] false, so a lone surviving match is NOT mistaken
/// for a confident unique pin.
typedef CourseMatches = ({List<Room> matches, bool complete});

class ActivityCourseResolver {
  /// The genuinely-pinned course-space id for an activity opened WITHOUT a
  /// selected course: the single eligible match, or null when the choice is
  /// ambiguous (0 or >1 matches) OR the match set is INCOMPLETE. Never an
  /// arbitrary `firstOrNull` pick, and never a lone survivor of a batch where
  /// another course's eligibility couldn't be resolved — either would
  /// mis-attribute the session's `source_course_id`, so anything short of a
  /// confident single match is left UNSCOPED.
  static String? unambiguousCourseId(CourseMatches matches) =>
      matches.complete && matches.matches.length == 1
      ? matches.matches.single.id
      : null;

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
  static Future<CourseMatches> matchingCourseSpaces(
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
    // No joined courses at all — a definitively complete (empty) answer.
    if (spaces.isEmpty) return (matches: const <Room>[], complete: true);

    final activityRefsResult = await QuestRepo.activityLearningObjectiveRefs(
      activityId,
    );

    final activityRefs = activityRefsResult.result?.toSet();
    if (activityRefs == null) {
      // The activity's own LO refs couldn't be read: eligibility is UNKNOWN for
      // every course, so report no matches AND incomplete — a caller must not
      // treat this as a confident "no course".
      return (matches: const <Room>[], complete: false);
    }
    if (activityRefs.isEmpty) {
      // The activity genuinely has no LOs, so no course can match — complete.
      return (matches: const <Room>[], complete: true);
    }

    String short(String code) => code.split('-').first.toLowerCase();

    final matching = <Room>[];
    // Flipped false the moment ANY course's eligibility can't be determined
    // (its quest didn't resolve). Single-threaded event loop, so concurrent
    // closures mutating this is safe.
    var complete = true;
    await Future.wait(
      spaces.map((space) async {
        try {
          final questResult = await QuestRepo.quest(space.coursePlan!.uuid);
          final quest = questResult.result;
          if (quest == null) {
            // Eligibility unknown for this course — the match set is incomplete.
            complete = false;
            return;
          }

          if (activityL2 != null &&
              short(quest.targetLanguage) != short(activityL2)) {
            return;
          }
          if (quest.learningObjectiveIds.any(activityRefs.contains)) {
            matching.add(space);
          }
        } catch (_) {
          // A course whose quest can't be resolved has UNKNOWN eligibility, not
          // "no match": mark the set incomplete so a lone survivor isn't pinned.
          complete = false;
        }
      }),
    );
    return (matches: matching, complete: complete);
  }
}
