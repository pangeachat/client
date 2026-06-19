import 'package:fluffychat/features/quests/repo/quest_repo.dart';

/// Holds the set of learning-objective ids across the learner's joined courses,
/// so world-map relevance banding can tell a joined-course activity from a
/// merely level-appropriate one without a per-pin lookup (see the Priority
/// matrix in world-map.instructions.md).
///
/// Rebuilt wholesale on course join/leave — the simplest invalidation, and the
/// set is small. Objective resolution is injectable so the rebuild is
/// unit-testable without Matrix or the network.
class JoinedObjectiveCache {
  Set<String> _ids = const {};

  /// The flattened, deduped objective-id set across all joined courses. Empty
  /// until the first [rebuild] completes.
  Set<String> get ids => _ids;

  /// Rebuild from the joined courses' quest outlines. [objectivesOf] maps a
  /// course-plan uuid to the ids of the objectives it covers (defaults to the
  /// v3 quest read layer). A course that fails to resolve is skipped rather than
  /// failing the whole set, so one bad course can't blank the banding.
  Future<void> rebuild(
    List<String> courseUuids, {
    Future<List<String>> Function(String uuid)? objectivesOf,
  }) async {
    final resolve = objectivesOf ?? _objectivesFromQuest;
    final next = <String>{};
    await Future.wait(
      courseUuids.map((uuid) async {
        try {
          next.addAll(await resolve(uuid));
        } catch (_) {
          // Skip a course that won't resolve; the rest still band correctly.
        }
      }),
    );
    _ids = next;
  }

  static Future<List<String>> _objectivesFromQuest(String uuid) async {
    final outline = await QuestRepo.outline(uuid);
    return outline.quest.learningObjectiveIds;
  }
}
