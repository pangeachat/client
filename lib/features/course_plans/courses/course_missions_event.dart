import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/cities/city_index.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/activity_family.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// The listed city a Mission's pinned activities fall under (org quests doc,
/// "A course is a trip"): a write-through cache the writer recomputes from
/// `activity_ids` on every publish, never edited on its own, there so a ship
/// can be placed from room state alone. Absent when no pin falls under a
/// listed city.
class MissionCity {
  final String name;
  final double lat;
  final double lng;
  const MissionCity({required this.name, required this.lat, required this.lng});

  LatLng get point => LatLng(lat, lng);

  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lng': lng};

  /// Strict: a name and a finite position on the globe, or null.
  static MissionCity? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final lat = raw['lat'];
    final lng = raw['lng'];
    if (name is! String ||
        name.isEmpty ||
        lat is bool ||
        lng is bool ||
        lat is! num ||
        lng is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      return null;
    }
    return MissionCity(name: name, lat: lat.toDouble(), lng: lng.toDouble());
  }

  /// The same city: by position, since the name alone repeats (two Suzhous).
  bool sameAs(MissionCity other) =>
      name == other.name && lat == other.lat && lng == other.lng;
}

/// One Mission (Can-Do) in a course's own copy: which Learning Objective, the
/// activity content ids that satisfy it in this course (its city slice), the
/// listed city those pins fall under, and the teacher's optional note and due
/// date.
class CourseMission {
  final String loId;
  final List<String> activityIds;

  /// Activities the teacher hid or removed in this Can-Do: not shown to
  /// students, still credited to the Can-Do. Showing one again moves it back
  /// to [activityIds].
  final List<String> removedActivityIds;
  final String? note;

  /// A UTC instant: the day the course moves on from this Mission's city. On
  /// a dated course it closes the city (org quests doc, "Progression");
  /// assigned activities stay playable after it. Null on an undated course.
  final DateTime? dueAt;

  /// The listed city the pins fall under (version 2); null on a version 1
  /// record and for a Mission whose pins fall under no listed city.
  final MissionCity? city;

  const CourseMission({
    required this.loId,
    required this.activityIds,
    this.removedActivityIds = const [],
    this.note,
    this.dueAt,
    this.city,
  });

  Map<String, dynamic> toJson() => {
    'lo_id': loId,
    'activity_ids': activityIds,
    if (removedActivityIds.isNotEmpty)
      'removed_activity_ids': removedActivityIds,
    if (note != null) 'note': note,
    if (dueAt != null) 'due_at': dueAt!.toUtc().toIso8601String(),
    if (city != null) 'city': city!.toJson(),
  };
}

/// A Can-Do the teacher removed: not shown, but its activities stay credited
/// to the course total. [activityIds] holds every credited id of the Can-Do at
/// removal (its shown ids, then its hidden ones); the first [shownCount] were
/// shown, so restoring it puts those back and keeps the rest hidden.
class RemovedMission {
  final String loId;
  final List<String> activityIds;
  final int shownCount;

  const RemovedMission({
    required this.loId,
    required this.activityIds,
    required this.shownCount,
  });

  Map<String, dynamic> toJson() => {
    'lo_id': loId,
    'activity_ids': activityIds,
    'shown_count': shownCount,
  };
}

/// The `pangea.course_missions` course-space state event: the course's own
/// frozen copy of its Can-Do list (content-studio.instructions.md). When it is
/// valid the course reads only this list; when it is absent or invalid every
/// reader behaves exactly as before it existed (shared quest order plus the
/// teacher-mode pins).
///
/// Version 1 is the list with notes and dates. Version 2 (pangeachat/.github#780)
/// is the trip: the same list sliced to one city per Can-Do, each Mission
/// carrying its [MissionCity], and a `start_date` when the course runs by
/// dates. A reader of either version treats any other as absent.
class CourseMissionsEvent {
  static const int schemaVersion = 1;
  static const int tripVersion = 2;
  static const Set<int> supportedVersions = {schemaVersion, tripVersion};
  static const int maxNoteLength = 280;
  static final RegExp _hasUtcOffset = RegExp(r'T.*(Z|[+-]\d{2}:?\d{2})$');
  static final RegExp _isDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  final int version;
  final int revision;
  final String? timeZone;

  /// The course's first day (version 2), a date in the course time zone.
  /// Present only on a dated course: with it cities open by the calendar,
  /// without it by progress (org quests doc, "Progression").
  final DateTime? startDate;
  final List<CourseMission> missions;

  /// Can-Dos the teacher removed; empty on every v1 record. Readers that
  /// predate it ignore the field.
  final List<RemovedMission> removedMissions;

  const CourseMissionsEvent({
    required this.revision,
    required this.missions,
    this.version = schemaVersion,
    this.removedMissions = const [],
    this.timeZone,
    this.startDate,
  });

  /// Whether this copy is the trip (version 2): sliced into cities.
  bool get isTrip => version == tripVersion;

  /// Whether the course runs by the calendar (a start date) rather than by
  /// each student's progress.
  bool get isDated => startDate != null;

  /// Every Can-Do the record names: the shown ones and the removed ones.
  Set<String> get allLoIds => {
    for (final m in missions) m.loId,
    for (final m in removedMissions) m.loId,
  };

  Map<String, dynamic> toJson() => {
    'version': version,
    'revision': revision,
    if (timeZone != null) 'time_zone': timeZone,
    if (startDate != null) 'start_date': _dateString(startDate!),
    'missions': [for (final m in missions) m.toJson()],
    if (removedMissions.isNotEmpty)
      'removed_missions': [for (final m in removedMissions) m.toJson()],
  };

  static String _dateString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Strict parse: any field of the wrong type, a version other than 1 or 2,
  /// a revision below 1, a duplicate Can-Do, an over-long note, an unreadable
  /// due date, start date or city makes the whole record invalid (null), so a
  /// malformed copy can never half-apply. A version 1 record's `start_date`
  /// and `city` fields, if any, are ignored: they belong to version 2.
  static CourseMissionsEvent? tryParse(Object? content) {
    if (content is! Map) return null;
    final version = content['version'];
    if (version is! int || !supportedVersions.contains(version)) return null;
    final trip = version == tripVersion;
    final revision = content['revision'];
    if (revision is! int || revision < 1) return null;
    final timeZone = content['time_zone'];
    if (timeZone != null && (timeZone is! String || timeZone.isEmpty)) {
      return null;
    }
    DateTime? startDate;
    final rawStart = trip ? content['start_date'] : null;
    if (rawStart != null) {
      if (rawStart is! String || !_isDate.hasMatch(rawStart)) return null;
      startDate = DateTime.tryParse(rawStart);
      if (startDate == null) return null;
      startDate = DateTime(startDate.year, startDate.month, startDate.day);
    }
    final rawMissions = content['missions'];
    if (rawMissions is! List) return null;

    final missions = <CourseMission>[];
    final seen = <String>{};
    for (final raw in rawMissions) {
      if (raw is! Map) return null;
      final loId = raw['lo_id'];
      if (loId is! String || loId.isEmpty || !seen.add(loId)) return null;
      final rawIds = raw['activity_ids'];
      if (rawIds is! List || rawIds.any((id) => id is! String)) return null;
      final rawRemoved = raw['removed_activity_ids'];
      if (rawRemoved != null &&
          (rawRemoved is! List || rawRemoved.any((id) => id is! String))) {
        return null;
      }
      final note = raw['note'];
      if (note != null && (note is! String || note.length > maxNoteLength)) {
        return null;
      }
      final rawDue = raw['due_at'];
      DateTime? dueAt;
      if (rawDue != null) {
        // An instant: a bare local time or date would read in the viewer's
        // zone, so the offset (or Z) is required.
        if (rawDue is! String || !_hasUtcOffset.hasMatch(rawDue)) return null;
        dueAt = DateTime.tryParse(rawDue)?.toUtc();
        if (dueAt == null) return null;
      }
      MissionCity? city;
      final rawCity = trip ? raw['city'] : null;
      if (rawCity != null) {
        city = MissionCity.tryParse(rawCity);
        if (city == null) return null;
      }
      missions.add(
        CourseMission(
          loId: loId,
          activityIds: rawIds.cast<String>().toSet().toList(),
          removedActivityIds: rawRemoved == null
              ? const []
              : (rawRemoved as List).cast<String>().toSet().toList(),
          note: note as String?,
          dueAt: dueAt,
          city: city,
        ),
      );
    }
    final removedMissions = <RemovedMission>[];
    final rawRemovedMissions = content['removed_missions'];
    if (rawRemovedMissions != null) {
      if (rawRemovedMissions is! List) return null;
      for (final raw in rawRemovedMissions) {
        if (raw is! Map) return null;
        final loId = raw['lo_id'];
        final ids = raw['activity_ids'];
        final shownCount = raw['shown_count'];
        if (loId is! String ||
            loId.isEmpty ||
            ids is! List ||
            ids.any((id) => id is! String) ||
            shownCount is! int ||
            shownCount < 0 ||
            shownCount > ids.length) {
          return null;
        }
        removedMissions.add(
          RemovedMission(
            loId: loId,
            activityIds: ids.cast<String>().toList(),
            shownCount: shownCount,
          ),
        );
      }
    }
    return CourseMissionsEvent(
      version: version,
      revision: revision,
      timeZone: timeZone as String?,
      startDate: startDate,
      missions: missions,
      removedMissions: removedMissions,
    );
  }

  /// The copy a new course starts with. With [cities] (the listed cities),
  /// the trip: every Can-Do in order, sliced to the activities under the
  /// listed city most of its pins fall under ([sliceFor]), undated. Without
  /// them, the version 1 snapshot: every Can-Do with every activity shown
  /// for it. No time zone (dates show in the viewer's zone until the
  /// Studio's first publish sets one).
  static CourseMissionsEvent snapshotOf(
    QuestOutline outline, {
    int revision = 1,
    CityIndex? cities,
  }) => CourseMissionsEvent(
    version: cities == null ? schemaVersion : tripVersion,
    revision: revision,
    missions: [
      for (final group in outline.groups)
        if (cities == null)
          CourseMission(
            loId: group.objective.id,
            activityIds: [for (final a in group.activities) a.activityId],
          )
        else
          sliceFor(group, cities),
    ],
  );

  /// A Can-Do's city slice (org quests doc, "A course is a trip"; the Create
  /// my class rule on pangeachat/.github#780): the listed city most of its
  /// activities fall under, ties to the first activity's city, and the pins
  /// are its activities under that city. A Can-Do with no activity under a
  /// listed city keeps every activity and has no city; it is still playable
  /// and does not move the ship.
  static CourseMission sliceFor(QuestObjectiveGroup group, CityIndex cities) {
    final byCity = <String, (ListedCity, List<String>)>{};
    for (final activity in group.activities) {
      final point = activity.point;
      if (point == null) continue;
      final city = cities.nearest(point);
      if (city == null) continue;
      (byCity[city.key] ??= (city, [])).$2.add(activity.activityId);
    }
    if (byCity.isEmpty) {
      return CourseMission(
        loId: group.objective.id,
        activityIds: [for (final a in group.activities) a.activityId],
      );
    }
    var best = byCity.values.first;
    for (final candidate in byCity.values) {
      if (candidate.$2.length > best.$2.length) best = candidate;
    }
    final (city, ids) = best;
    return CourseMission(
      loId: group.objective.id,
      activityIds: ids,
      city: MissionCity(name: city.name, lat: city.lat, lng: city.lng),
    );
  }

  /// The Mission ids this copy lists that [quest] still carries, in the
  /// copy's order — the effective Can-Do list for a reader that has only the
  /// quest, not the full outline.
  List<String> loIdsWithin(QuestPlan quest) {
    final questLoIds = quest.learningObjectiveIds.toSet();
    return [
      for (final m in missions)
        if (questLoIds.contains(m.loId)) m.loId,
    ];
  }

  /// Whether [activityId] belongs to this course: listed under a Can-Do the
  /// quest still carries and that the activity itself satisfies.
  bool listsActivity(
    QuestPlan quest,
    String activityId,
    Set<String> activityLoRefs,
  ) {
    final questLoIds = quest.learningObjectiveIds.toSet();
    return missions.any(
      (m) =>
          questLoIds.contains(m.loId) &&
          activityLoRefs.contains(m.loId) &&
          m.activityIds.contains(activityId),
    );
  }
}

/// What a course room says about its own Can-Do list: its copy, if valid, and
/// the teacher-mode pins (used only when there is no copy).
class CourseListRules {
  final CourseMissionsEvent? missions;
  final Map<String, List<String>>? pins;
  const CourseListRules({this.missions, this.pins});

  /// No room: the shared quest, unrestricted.
  static const none = CourseListRules();

  /// The copy's revision, 0 when there is none — what a refresh compares.
  int get revision => missions?.revision ?? 0;
}

extension CourseMissionsRoomExtension on Room {
  /// The course's own copy, or null when absent, malformed, or sent by
  /// someone who is not a course admin (power level 100) in this room now — a
  /// student can never forge their own list or due dates.
  CourseMissionsEvent? get courseMissions {
    final event = getState(PangeaEventTypes.courseMissions);
    if (event == null) return null;
    if (getPowerLevelByUserId(event.senderId) <
        SpaceConstants.powerLevelOfAdmin) {
      return null;
    }
    return CourseMissionsEvent.tryParse(event.content);
  }

  CourseListRules get courseListRules => CourseListRules(
    missions: courseMissions,
    pins: teacherMode.pinnedActivitiesByObjective,
  );
}

extension QuestOutlineForCourse on QuestOutline {
  /// This outline as [room]'s course shows it — the one helper every reader of
  /// a course's Can-Dos goes through. Null [room] (previews, no joined course)
  /// is the shared quest, unrestricted.
  QuestOutline forCourse(Room? room) =>
      forRules(room?.courseListRules ?? CourseListRules.none);

  /// The pure transform behind [forCourse]. A PURE COPY: the outline cache is
  /// shared across courses built from one quest, so this never mutates it.
  ///
  /// With a copy: the copy's Can-Dos in its order (ones the quest no longer
  /// carries drop), each with the copy's activity ids that the library still
  /// returns (in the copy's order), plus the note and due date. The
  /// quest's sequence is reordered to match, so
  /// [QuestOutline.toCourseLoOutline]'s `orderedLoIds` follows the copy too.
  /// A Can-Do the copy lists that the quest does not carry (one a teacher
  /// added) comes from the listing's own Can-Dos ([addedGroups]).
  ///
  /// The listing also returns the course's own copies of activities; only the
  /// ids the copy lists are shown. Everything the copy credits — shown,
  /// hidden, and in removed Can-Dos — is gathered into [QuestOutline.credit]
  /// so progress follows an activity across its copies.
  /// Without a copy: exactly today's pin restriction.
  QuestOutline forRules(CourseListRules rules) {
    final copy = rules.missions;
    if (copy == null) return restrictedTo(rules.pins);

    final credit = _creditFor(copy);
    final groupsById = {
      for (final g in [...groups, ...addedGroups]) g.objective.id: g,
    };
    final stepsById = {for (final s in quest.sequence) s.objective.id: s};
    final nextGroups = <QuestObjectiveGroup>[];
    final nextSteps = <QuestObjectiveStep>[];
    for (final mission in copy.missions) {
      final group = groupsById[mission.loId];
      if (group == null) continue;
      // Shown in the record's order: a teacher can reorder a Can-Do's
      // activities (Content Studio v2). Records written before that listed
      // the library's order, so they read as they always did. An id the
      // listing no longer returns is dropped.
      final hidden = mission.removedActivityIds.toSet();
      final listedIds = mission.activityIds.toSet();
      // Family members of what this Can-Do shows (an original the record
      // does not name) are credited here too, so their words count.
      final creditedHere = {
        for (final id in [
          ...mission.activityIds,
          ...mission.removedActivityIds,
        ])
          credit.canonicalOf(id),
      };
      final available = {for (final a in group.activities) a.activityId: a};
      final shown = [
        for (final id in mission.activityIds)
          if (available[id] != null) available[id]!,
      ];
      final pacing = MissionPacing(
        note: mission.note,
        dueAt: mission.dueAt,
        timeZone: copy.timeZone,
        city: mission.city,
      );
      nextGroups.add(
        QuestObjectiveGroup(
          objective: group.objective,
          activities: shown,
          pacing: pacing.isEmpty ? null : pacing,
          credit: credit,
          hiddenActivities: [
            for (final a in group.activities)
              if (!listedIds.contains(a.activityId) &&
                  (hidden.contains(a.activityId) ||
                      (credit.family.containsKey(a.activityId) &&
                          creditedHere.contains(
                            credit.canonicalOf(a.activityId),
                          ))))
                a,
          ],
        ),
      );
      nextSteps.add(
        stepsById[mission.loId] ??
            QuestObjectiveStep(objective: group.objective, wasMinted: false),
      );
    }
    return withCourse(
      quest: quest.withSequence(nextSteps),
      groups: nextGroups,
      credit: credit,
      trip: copy.isTrip
          ? CourseTrip(startDate: copy.startDate, timeZone: copy.timeZone)
          : null,
    );
  }

  /// What [copy] credits: its activities in course order (each Can-Do's shown
  /// ids, then its hidden ones, then the removed Can-Dos'), grouped into
  /// families from the listing. [CourseCredit.none] when no activity has a
  /// copy and nothing is hidden or removed, so a course without copies reads
  /// exactly as it did before they existed.
  CourseCredit _creditFor(CourseMissionsEvent copy) {
    ListedActivity listed(String id, {required bool shown}) => ListedActivity(
      activityId: id,
      familyIds: familyIdsByActivity[id] ?? const [],
      shown: shown,
    );
    final credited = <ListedActivity>[
      for (final m in copy.missions) ...[
        for (final id in m.activityIds) listed(id, shown: true),
        for (final id in m.removedActivityIds) listed(id, shown: false),
      ],
      for (final rm in copy.removedMissions)
        for (final id in rm.activityIds) listed(id, shown: false),
    ];
    final hasHidden =
        copy.removedMissions.isNotEmpty ||
        copy.missions.any((m) => m.removedActivityIds.isNotEmpty);
    final hasFamily = credited.any(
      (a) => a.familyIds.any((id) => id != a.activityId),
    );
    if (!hasHidden && !hasFamily) return CourseCredit.none;
    return CourseCredit(
      family: activityFamily(credited),
      removedByLo: {
        for (final m in copy.missions)
          if (m.removedActivityIds.isNotEmpty) m.loId: m.removedActivityIds,
      },
      removedMissionActivityIds: {
        for (final rm in copy.removedMissions) ...rm.activityIds,
      },
      shownIds: {for (final m in copy.missions) ...m.activityIds},
    );
  }
}

/// The course-scoped map's marker filter: the cards [rules] lets this course
/// show. With a copy, a card stays when a listed Can-Do it satisfies lists it;
/// without one, today's fail-open pin rule ([effectivePinnedActivityIds]).
List<QuestActivityCard> restrictCardsForCourse(
  List<QuestActivityCard> cards,
  CourseListRules rules,
) {
  final copy = rules.missions;
  if (copy != null) {
    final allowedByLo = {
      for (final m in copy.missions) m.loId: m.activityIds.toSet(),
    };
    return cards
        .where(
          (card) => card.learningObjectiveRefs.any(
            (loId) => allowedByLo[loId]?.contains(card.activityId) ?? false,
          ),
        )
        .toList();
  }
  final pinnedByObjective = rules.pins;
  if (pinnedByObjective == null || pinnedByObjective.isEmpty) return cards;
  final availableByLo = <String, Set<String>>{};
  for (final card in cards) {
    for (final loId in card.learningObjectiveRefs) {
      (availableByLo[loId] ??= <String>{}).add(card.activityId);
    }
  }
  final allowedByLo = {
    for (final entry in availableByLo.entries)
      entry.key: effectivePinnedActivityIds(
        entry.value,
        pinnedByObjective[entry.key],
      ),
  };
  return cards
      .where(
        (card) => card.learningObjectiveRefs.any(
          (loId) => allowedByLo[loId]?.contains(card.activityId) ?? true,
        ),
      )
      .toList();
}
