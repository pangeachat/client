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

  /// The copy's revision the indexes refer to: a publish that reorders or
  /// removes Can-Dos makes them name other Missions, so a position of
  /// another revision is ignored until the homeserver writes a fresh one.
  final int revision;
  const CoursePositionEvent({
    required this.stop,
    required this.fromStop,
    required this.since,
    required this.revision,
  });

  static CoursePositionEvent? tryParse(Object? content) {
    if (content is! Map) return null;
    final stop = content['stop'];
    final fromStop = content['from_stop'];
    final since = content['since'];
    final revision = content['revision'];
    if (stop is! int ||
        fromStop is! int ||
        since is! int ||
        revision is! int ||
        stop < 0 ||
        fromStop < 0 ||
        since < 0 ||
        revision < 1) {
      return null;
    }
    return CoursePositionEvent(
      stop: stop,
      fromStop: fromStop,
      since: since,
      revision: revision,
    );
  }

  /// [stop] when this position belongs to [copy] (its revision, and a stop
  /// the copy has), else null.
  int? stopIn(CourseMissionsEvent copy) =>
      revision == copy.revision && stop < copy.missions.length ? stop : null;
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
  /// [position]. A Mission with no city does not move the ship (org quests
  /// doc, "Progression"), so it stays at the last Mission with a city before
  /// that, or the first one with a city. Null for a record that is not a
  /// trip, so a course from before trips moves no camera by itself.
  static int? shipStopOf(
    CourseMissionsEvent copy,
    CoursePositionEvent? position,
    DateTime now,
  ) {
    if (!copy.isTrip || copy.missions.isEmpty) return null;
    final stop = copy.isDated
        ? _datedStopOf([for (final m in copy.missions) m.dueAt], now) ?? 0
        : position?.stopIn(copy) ?? 0;
    return _locatedStop(copy.missions, stop);
  }

  /// [stop], or the Mission with a city the ship stays at when [stop] has
  /// none: the last one before it, else the first one after it. [stop] as
  /// is when no Mission has a city.
  static int _locatedStop(List<CourseMission> missions, int stop) {
    for (var i = stop; i >= 0; i--) {
      if (missions[i].city != null) return i;
    }
    for (var i = stop + 1; i < missions.length; i++) {
      if (missions[i].city != null) return i;
    }
    return stop;
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
    if (copy == null) return null;
    final stop = position?.stopIn(copy);
    if (stop == null) return null;
    final shipMissionId = copy.missions[stop].loId;
    final index = groups.indexWhere((g) => g.objective.id == shipMissionId);
    return index < 0 ? null : index;
  }

  /// How long both cities stay open after a dated city's date passes: the
  /// ship takes about a day to arrive, so stragglers catch up, then the old
  /// city closes (org quests doc, "Progression").
  static const Duration transit = Duration(days: 1);

  /// The ids of the Missions open to the learner, or null when nothing is
  /// closed: the course is not a trip, or ([progressResolved] false) the
  /// learner's progress is not known yet, so nothing is locked on a guess.
  /// Open: the city the course is at; on a dated course the city it just
  /// left, for [transit]; every Mission the learner completed; every one a
  /// teacher opened for them. A past city the learner never finished closes.
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
    final ids = [for (final g in groups) g.objective.id];
    final open = _openStops(
      dueDates: [for (final g in groups) g.pacing?.dueAt],
      isDated: trip.isDated,
      startDate: trip.startDate,
      now: now,
      progressResolved: progressResolved,
      anchorIndex: anchorId == null ? -1 : ids.indexOf(anchorId),
    );
    if (open == null) return null;
    return _openIds(ids, open, completedIds, reopenedIds);
  }

  /// [openMissionIds] from the course record alone, for a surface with no
  /// outline, such as the world view's cities: the same rule over the
  /// copy's Missions, keyed by Can-Do id. Null when nothing is closed.
  static Set<String>? openMissionIdsOf({
    required CourseMissionsEvent copy,
    required DateTime now,
    required bool progressResolved,
    required String? anchorId,
    required Set<String> completedIds,
    required Set<String> reopenedIds,
  }) {
    if (!copy.isTrip || copy.missions.isEmpty) return null;
    final ids = [for (final m in copy.missions) m.loId];
    final open = _openStops(
      dueDates: [for (final m in copy.missions) m.dueAt],
      isDated: copy.isDated,
      startDate: copy.startDate,
      now: now,
      progressResolved: progressResolved,
      anchorIndex: anchorId == null ? -1 : ids.indexOf(anchorId),
    );
    if (open == null) return null;
    return _openIds(ids, open, completedIds, reopenedIds);
  }

  static Set<String> _openIds(
    List<String> ids,
    Set<int> open,
    Set<String> completedIds,
    Set<String> reopenedIds,
  ) => {
    for (final (i, id) in ids.indexed)
      if (open.contains(i) ||
          completedIds.contains(id) ||
          reopenedIds.contains(id))
        id,
  };

  /// The open stops by the one rule ([openMissionIds] states it), over the
  /// Missions' due dates in order; null when the learner's progress is not
  /// known yet on an undated trip.
  static Set<int>? _openStops({
    required List<DateTime?> dueDates,
    required bool isDated,
    required DateTime? startDate,
    required DateTime now,
    required bool progressResolved,
    required int anchorIndex,
  }) {
    final open = <int>{};
    if (isDated) {
      if (startDate != null && now.isBefore(startDate)) {
        open.add(0);
      } else {
        final current = _datedStopOf(dueDates, now) ?? dueDates.length - 1;
        open.add(current);
        // The city just left stays open while the ship is in transit.
        for (var i = current - 1; i >= 0; i--) {
          final dueAt = dueDates[i];
          if (dueAt == null) continue;
          if (now.difference(dueAt) < transit) open.add(i);
          break;
        }
      }
    } else {
      if (!progressResolved) return null;
      // No anchor: every Mission is complete, so every one is open.
      if (anchorIndex < 0) {
        open.addAll(List.generate(dueDates.length, (i) => i));
      } else {
        open.add(anchorIndex);
      }
    }
    return open;
  }
}
