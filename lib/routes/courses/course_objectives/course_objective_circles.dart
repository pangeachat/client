import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/discovered_sessions_cache.dart';
import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/course_itinerary.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/courses/course_objectives/activity_live_state_room_extension.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_progress_circles.dart';
import 'package:fluffychat/routes/world/world_map_pins_manager.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// The circles for a course, read from its shared resolver: Missions with an
/// activity in plan order, complete when their XP is at the threshold, the
/// Mission on show pointed at (the current one unless the learner picked
/// another). Nothing while the plan is still loading.
class CourseObjectiveCircles extends StatelessWidget {
  final QuestObjectivesLoader objectivesProvider;

  /// Tapping a circle, with its Mission's id; null draws the circles inert.
  final void Function(String missionId)? onSelectMission;

  /// The Mission the course page shows, to point at; null points at the
  /// current one.
  final String? selectedMissionId;

  /// Passed through to [ObjectiveProgressCircles.showSelectedLabel].
  final bool showSelectedLabel;

  const CourseObjectiveCircles({
    required this.objectivesProvider,
    this.onSelectMission,
    this.selectedMissionId,
    this.showSelectedLabel = false,
    super.key,
  });

  /// Where the class is: the itinerary's current city (org quests doc,
  /// "Progression") — a dated trip's by its dates, an undated trip's ship
  /// from the course space, and a course that is not a trip by the teacher's
  /// due dates as before. Null when unknown.
  static int? classLocationIndex(
    List<QuestObjectiveGroup> groups,
    DateTime now, {
    CourseTrip? trip,
    Room? course,
  }) => CourseItinerary.classStop(
    groups: groups,
    trip: trip,
    position: course?.coursePosition,
    copy: course?.courseMissions,
    now: now,
  );

  /// The Missions open to the learner on the course's trip, or null when
  /// nothing is closed ([CourseItinerary.openMissionIds]).
  static Set<String>? openMissionIds(
    QuestObjectivesLoader objectivesProvider,
    Room? course,
    DateTime now,
  ) {
    final groups = objectivesProvider.filteredObjectiveGroups;
    final resolved = objectivesProvider.hasResolvedProgress;
    final userId = course?.client.userID;
    return CourseItinerary.openMissionIds(
      groups: groups,
      trip: objectivesProvider.trip,
      now: now,
      progressResolved: resolved && !objectivesProvider.progressLoading,
      anchorId: objectivesProvider.currentObjectiveGroup?.objective.id,
      completedIds: {
        for (final g in groups)
          if (objectivesProvider.missionProgress(g.objective.id)?.satisfied ==
              true)
            g.objective.id,
      },
      reopenedIds: course == null || userId == null
          ? const {}
          : course.missionsOpenedFor(userId),
    );
  }

  /// Whether a coursemate pinged a session of [group] that is still open to
  /// join — the bell on its circle, since the map shows only the Mission on
  /// show.
  static bool _hasPing(
    Room course,
    QuestObjectiveGroup group,
    Set<String> pinged,
  ) => group.activities.any(
    (a) =>
        pinged.contains(a.activityId) &&
        course.activityLiveState(a.activityId).state ==
            ActivityPinState.joinable,
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      objectivesProvider.questLoader,
      objectivesProvider.progression,
      MissionXpCache.instance,
      WorldMapPinsManager.pingedActivityIds,
      DiscoveredSessionsCache.instance,
    ]),
    builder: (context, _) {
      final groups = objectivesProvider.filteredObjectiveGroups;
      final courseId = objectivesProvider.courseId;
      final course = courseId == null
          ? null
          : objectivesProvider.client.getRoomById(courseId);
      final currentId = objectivesProvider.currentObjectiveGroup?.objective.id;
      final loading = objectivesProvider.progressLoading;
      // While progress loads the current Mission isn't known yet (it falls
      // back to the first), so no circle is pointed at unless the learner
      // picked one — the pointer would land on Mission 1, then jump (#9559).
      final shownId =
          objectivesProvider.objectiveGroup(selectedMissionId)?.objective.id ??
          (loading ? null : currentId);
      final pinged = WorldMapPinsManager.pingedActivityIds.value;
      final now = DateTime.now();
      final classIndex = classLocationIndex(
        groups,
        now,
        trip: objectivesProvider.trip,
        course: course,
      );
      final open = openMissionIds(objectivesProvider, course, now);
      final onSelectMission = this.onSelectMission;
      return ObjectiveProgressCircles(
        onTap: onSelectMission == null
            ? null
            : (index) => onSelectMission(groups[index - 1].objective.id),
        showSelectedLabel: showSelectedLabel,
        reserveClassLocation: showSelectedLabel,
        items: [
          for (final (i, group) in groups.indexed)
            if (objectivesProvider.missionProgress(group.objective.id)
                case final progress)
              ObjectiveCircleData(
                index: i + 1,
                statement: group.objective.objective,
                selected: group.objective.id == shownId,
                classLocation: i == classIndex,
                closed: open != null && !open.contains(group.objective.id),
                pinged:
                    course != null &&
                    group.objective.id != shownId &&
                    _hasPing(course, group, pinged),
                progress: progress?.fraction ?? 0.0,
                xp: progress,
                loading: loading,
                state: progress?.satisfied == true
                    ? ObjectiveCircleState.complete
                    : group.objective.id == currentId
                    ? ObjectiveCircleState.current
                    : ObjectiveCircleState.later,
              ),
        ],
      );
    },
  );
}
