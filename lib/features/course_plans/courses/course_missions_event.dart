import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/activity_family.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// One Mission (Can-Do) in a course's own copy: which Learning Objective, the
/// activity content ids that satisfy it in this course, and the teacher's
/// optional note and soft due date.
class CourseMission {
  final String loId;
  final List<String> activityIds;

  /// Activities the teacher hid or removed in this Can-Do: not shown to
  /// students, still credited to the Can-Do. Showing one again moves it back
  /// to [activityIds].
  final List<String> removedActivityIds;
  final String? note;

  /// A UTC instant. Shown, never enforced: nothing is blocked after it.
  final DateTime? dueAt;

  const CourseMission({
    required this.loId,
    required this.activityIds,
    this.removedActivityIds = const [],
    this.note,
    this.dueAt,
  });

  Map<String, dynamic> toJson() => {
    'lo_id': loId,
    'activity_ids': activityIds,
    if (removedActivityIds.isNotEmpty)
      'removed_activity_ids': removedActivityIds,
    if (note != null) 'note': note,
    if (dueAt != null) 'due_at': dueAt!.toUtc().toIso8601String(),
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
class CourseMissionsEvent {
  static const int schemaVersion = 1;
  static const int maxNoteLength = 280;
  static final RegExp _hasUtcOffset = RegExp(r'T.*(Z|[+-]\d{2}:?\d{2})$');

  final int revision;
  final String? timeZone;
  final List<CourseMission> missions;

  /// Can-Dos the teacher removed; empty on every v1 record. Readers that
  /// predate it ignore the field.
  final List<RemovedMission> removedMissions;

  const CourseMissionsEvent({
    required this.revision,
    required this.missions,
    this.removedMissions = const [],
    this.timeZone,
  });

  /// Every Can-Do the record names: the shown ones and the removed ones.
  Set<String> get allLoIds => {
    for (final m in missions) m.loId,
    for (final m in removedMissions) m.loId,
  };

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'revision': revision,
    if (timeZone != null) 'time_zone': timeZone,
    'missions': [for (final m in missions) m.toJson()],
    if (removedMissions.isNotEmpty)
      'removed_missions': [for (final m in removedMissions) m.toJson()],
  };

  /// Strict parse: any field of the wrong type, a version other than 1, a
  /// revision below 1, a duplicate Can-Do, an over-long note or an unreadable
  /// due date makes the whole record invalid (null), so a malformed copy can
  /// never half-apply.
  static CourseMissionsEvent? tryParse(Object? content) {
    if (content is! Map) return null;
    if (content['version'] != schemaVersion) return null;
    final revision = content['revision'];
    if (revision is! int || revision < 1) return null;
    final timeZone = content['time_zone'];
    if (timeZone != null && (timeZone is! String || timeZone.isEmpty)) {
      return null;
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
      missions.add(
        CourseMission(
          loId: loId,
          activityIds: rawIds.cast<String>().toSet().toList(),
          removedActivityIds: rawRemoved == null
              ? const []
              : (rawRemoved as List).cast<String>().toSet().toList(),
          note: note as String?,
          dueAt: dueAt,
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
      revision: revision,
      timeZone: timeZone as String?,
      missions: missions,
      removedMissions: removedMissions,
    );
  }

  /// The copy a new course starts with: a snapshot of the list it shows
  /// without one — every Can-Do in order, each with the activities shown for
  /// it. No time zone (dates show in the viewer's zone until the Studio's
  /// first publish sets one).
  static CourseMissionsEvent snapshotOf(
    QuestOutline outline, {
    int revision = 1,
  }) => CourseMissionsEvent(
    revision: revision,
    missions: [
      for (final group in outline.groups)
        CourseMission(
          loId: group.objective.id,
          activityIds: [for (final a in group.activities) a.activityId],
        ),
    ],
  );

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
  /// returns (in the library's order), plus the note and due date. The
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

    final groupsById = {
      for (final g in [...groups, ...addedGroups]) g.objective.id: g,
    };
    final stepsById = {for (final s in quest.sequence) s.objective.id: s};
    final nextGroups = <QuestObjectiveGroup>[];
    final nextSteps = <QuestObjectiveStep>[];
    for (final mission in copy.missions) {
      final group = groupsById[mission.loId];
      if (group == null) continue;
      // The copy's activity ids are a set in v1: writers snapshot from
      // different listings (this app's creation copy, the dashboard's publish,
      // the backfill), so their order is not a teacher's choice. Keeping the
      // library order means writing a copy never reorders what a student sees.
      final listed = mission.activityIds.toSet();
      final pacing = MissionPacing(
        note: mission.note,
        dueAt: mission.dueAt,
        timeZone: copy.timeZone,
      );
      nextGroups.add(
        QuestObjectiveGroup(
          objective: group.objective,
          activities: [
            for (final a in group.activities)
              if (listed.contains(a.activityId)) a,
          ],
          pacing: pacing.isEmpty ? null : pacing,
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
      credit: _creditFor(copy),
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
