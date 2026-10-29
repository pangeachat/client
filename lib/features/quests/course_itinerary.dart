import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// The `pangea.course_position` course-space state event: where an undated
/// course's ship is, written by the homeserver's position pass
/// (synapse-pangea-chat course-trip doc; pangeachat/.github#780). Indexes
/// into the copy's `missions[]`: a route may visit one city twice, and the
/// busiest stop can move backward. Never counts and never anyone's position.
class CoursePositionEvent {
  final int stop;
  final int fromStop;

  /// Milliseconds since the epoch when the ship set off for [stop].
  final int since;
  const CoursePositionEvent({
    required this.stop,
    required this.fromStop,
    required this.since,
  });

  static CoursePositionEvent? tryParse(Object? content) {
    if (content is! Map) return null;
    final stop = content['stop'];
    final fromStop = content['from_stop'];
    final since = content['since'];
    if (stop is! int ||
        fromStop is! int ||
        since is! int ||
        stop < 0 ||
        fromStop < 0 ||
        since < 0) {
      return null;
    }
    return CoursePositionEvent(stop: stop, fromStop: fromStop, since: since);
  }
}

/// The `pangea.course_access` course-space state event, one per student
/// (state key: their user id): the Missions a teacher opened for that student
/// ahead of the itinerary (org quests doc, "a teacher may open one for a
/// student"). `{"open": [<Mission id>, ...]}`, counted only when a course
/// admin sent it.
class CourseAccessEvent {
  final Set<String> openMissionIds;
  const CourseAccessEvent({required this.openMissionIds});

  static CourseAccessEvent? tryParse(Object? content) {
    if (content is! Map) return null;
    final open = content['open'];
    if (open is! List || open.any((id) => id is! String)) return null;
    return CourseAccessEvent(openMissionIds: open.cast<String>().toSet());
  }
}

extension CourseItineraryRoomExtension on Room {
  /// The ship's position, or null when none is written, it is malformed,
  /// or its sender is not a course admin now (a student cannot move the
  /// ship).
  CoursePositionEvent? get coursePosition {
    final event = getState(PangeaEventTypes.coursePosition);
    if (event == null) return null;
    if (getPowerLevelByUserId(event.senderId) <
        SpaceConstants.powerLevelOfAdmin) {
      return null;
    }
    return CoursePositionEvent.tryParse(event.content);
  }

  /// The Missions a teacher opened for [userId] ahead of the itinerary;
  /// empty when none, or when the record was not sent by a course admin.
  Set<String> missionsOpenedFor(String userId) {
    final event = getState(PangeaEventTypes.courseAccess, userId);
    if (event == null) return const {};
    if (getPowerLevelByUserId(event.senderId) <
        SpaceConstants.powerLevelOfAdmin) {
      return const {};
    }
    return CourseAccessEvent.tryParse(event.content)?.openMissionIds ??
        const {};
  }
}

/// Which Missions are open on a course's trip (org quests doc,
/// "Progression"; pangeachat/.github#780).
///
/// With dates, cities open by the calendar: a Mission's due date is the day
/// the course moves on from its city, so the course is at the first Mission
/// whose date is still ahead, and every Mission up to it is open. Without
/// dates, cities open by progress: a student starts at the first Mission and
/// completing it opens the next, so every Mission up to their first
/// incomplete one is open. Either way a Mission the student completed stays
/// open, and one a teacher opened for them is open. A course that is not a
/// trip (no copy, or a version 1 copy) closes nothing.
abstract final class CourseItinerary {
  /// The stop a dated course is at on [now]: the first Mission in order
  /// whose date is still ahead; every dated Mission past, the last dated one;
  /// before any date, the first Mission. Null for a course with no dates.
  static int? datedStop(List<QuestObjectiveGroup> groups, DateTime now) =>
      _datedStopOf([for (final g in groups) g.pacing?.dueAt], now);

  /// The one dated-stop rule over Missions' due dates in order, shared by
  /// [datedStop] (the outline) and [shipStopOf] (the record alone).
  static int? _datedStopOf(List<DateTime?> dueDates, DateTime now) {
    int? lastDated;
    for (var i = 0; i < dueDates.length; i++) {
      final dueAt = dueDates[i];
      if (dueAt == null) continue;
      if (dueAt.isAfter(now)) return i;
      lastDated = i;
    }
    return lastDated;
  }

  /// The stop a course's SHIP is at, read from its record alone (org
  /// course-view doc, "The camera": choosing a course fades to its ship's
  /// city): on a dated trip the first Mission whose date is still ahead (every
  /// date past, the last dated one); on an undated trip the ship's
  /// [position]; null for a record that is not a trip, so a course from before
  /// trips moves no camera by itself.
  static int? shipStopOf(
    CourseMissionsEvent copy,
    CoursePositionEvent? position,
    DateTime now,
  ) {
    if (!copy.isTrip || copy.missions.isEmpty) return null;
    if (copy.isDated) {
      return _datedStopOf([for (final m in copy.missions) m.dueAt], now) ?? 0;
    }
    final stop = position?.stop ?? 0;
    return stop < copy.missions.length ? stop : null;
  }

  /// The Mission the class is at, for the "Class location" mark: a dated
  /// trip's [datedStop]; an undated trip's ship ([position]); a course that
  /// is not a trip keeps the due-date rule it had. Null when unknown.
  ///
  /// The ship's stop indexes the record's whole `missions[]` ([copy]), while
  /// [groups] leaves out Missions with no activities, so the stop is resolved
  /// to its Mission id before it is placed among [groups].
  static int? classStop({
    required List<QuestObjectiveGroup> groups,
    required CourseTrip? trip,
    required CoursePositionEvent? position,
    required CourseMissionsEvent? copy,
    required DateTime now,
  }) {
    if (trip == null || trip.isDated) return datedStop(groups, now);
    final stop = position?.stop;
    final missions = copy?.missions;
    if (stop == null || missions == null || stop >= missions.length) {
      return null;
    }
    final shipMissionId = missions[stop].loId;
    final index = groups.indexWhere((g) => g.objective.id == shipMissionId);
    return index < 0 ? null : index;
  }

  /// The ids of the Missions open to the learner, or null when nothing is
  /// closed: the course is not a trip, or ([progressResolved] false) the
  /// learner's progress is not known yet, so nothing is locked on a guess.
  static Set<String>? openMissionIds({
    required List<QuestObjectiveGroup> groups,
    required CourseTrip? trip,
    required DateTime now,
    required bool progressResolved,
    required String? anchorId,
    required Set<String> completedIds,
    required Set<String> reopenedIds,
  }) {
    if (trip == null) return null;
    final int current;
    if (trip.isDated) {
      final start = trip.startDate;
      if (start != null && now.isBefore(start)) {
        current = 0;
      } else {
        current = datedStop(groups, now) ?? groups.length - 1;
      }
    } else {
      if (!progressResolved) return null;
      final anchor = anchorId == null
          ? -1
          : groups.indexWhere((g) => g.objective.id == anchorId);
      // No anchor: every Mission is complete, so every one is open.
      current = anchor < 0 ? groups.length - 1 : anchor;
    }
    return {
      for (final (i, group) in groups.indexed)
        if (i <= current ||
            completedIds.contains(group.objective.id) ||
            reopenedIds.contains(group.objective.id))
          group.objective.id,
    };
  }
}
