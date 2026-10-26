import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/course_language_scope.dart';
import 'package:fluffychat/features/quests/course_progress_event.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/mission_completion_replay.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// Keeps a progress record ([CourseProgressEvent]) for each joined course in
/// the learner's analytics room, for the teacher dashboard (client#9643).
/// Checked after every analytics upload and when a saved session starts to
/// count; a course is written only when one of its figures changed. A Mission
/// already complete when its course's record began gets its date replayed
/// from the learner's history ([MissionCompletionReplay]).
class CourseProgressWriter {
  /// The learner's cap-filtered uses in a language, read only when a
  /// completion date has to be replayed.
  final Future<List<OneConstructUse>> Function(String language) _readUses;

  CourseProgressWriter({
    required Future<List<OneConstructUse>> Function(String language) readUses,
  }) : _readUses = readUses;

  Future<void>? _inflight;
  Room? _queuedRoom;
  String? _queuedLanguage;

  /// What this run last wrote per course, until the room's state carries it:
  /// a check that ran before a write synced back would otherwise read the
  /// older record and date a completion a second time.
  final Map<String, CourseProgressEvent> _written = {};

  /// The current check's replay, built on the first Mission that needs one.
  MissionCompletionReplay? _replay;

  /// Course and Mission pairs whose replay found no date this run, so a
  /// failing replay isn't repeated after every upload.
  final Set<String> _unreplayable = {};

  /// Checks the courses in [language] and writes their records to
  /// [analyticsRoom], that language's analytics room. A check asked for while
  /// one runs runs once more after it, so the last change is never missed.
  Future<void> update(Room analyticsRoom, String language) {
    final inflight = _inflight;
    if (inflight != null) {
      _queuedRoom = analyticsRoom;
      _queuedLanguage = language;
      return inflight;
    }
    return _inflight = _run(analyticsRoom, language);
  }

  Future<void> _run(Room analyticsRoom, String language) async {
    try {
      await _check(analyticsRoom, language);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'analyticsRoomId': analyticsRoom.id, 'language': language},
      );
    } finally {
      _inflight = null;
      final queuedRoom = _queuedRoom;
      final queuedLanguage = _queuedLanguage;
      _queuedRoom = null;
      _queuedLanguage = null;
      if (queuedRoom != null && queuedLanguage != null) {
        unawaited(update(queuedRoom, queuedLanguage));
      }
    }
  }

  Future<void> _check(Room analyticsRoom, String language) async {
    final cache = MissionXpCache.instance..ensureWired();
    // Before the learner's XP has been read every Mission reads as zero, and
    // writing that would be wrong. The next upload checks again.
    if (!cache.hasReadFor(language)) return;
    final client = analyticsRoom.client;
    final courses = client.joinedCourseRooms
        .where(CourseLanguageScope.courseInTargetLanguage)
        .toList();
    if (courses.isEmpty) return;
    final xpByActivity = client.userXpByActivity(cache.creditedXpByRoom);
    final byActivity = client.cachedXpBreakdownByActivity;
    final appVersion = await _appVersion();
    _replay = null;
    for (final course in courses) {
      final outline = await _outlineOf(course);
      if (outline == null) continue;
      final xpToComplete =
          course.teacherMode.xpToCompleteObjective ??
          kDefaultXpToCompleteObjective;
      final stored = _storedFor(analyticsRoom, course.id);
      var next = CourseProgressEvent.after(
        stored: stored,
        xpToComplete: xpToComplete,
        canDos: client.canDoProgress(
          outline,
          xpToComplete: xpToComplete,
          xpByActivity: xpByActivity,
          byActivity: byActivity,
        ),
        now: DateTime.now().toUtc(),
        appVersion: appVersion,
      );
      final awaiting = [
        for (final missionId in next.awaitingReplay)
          if (!_unreplayable.contains('${course.id}|$missionId')) missionId,
      ];
      if (awaiting.isNotEmpty) {
        final replay = _replay ??= MissionCompletionReplay(
          uses: await _readUses(language),
          sessions: client.savedSessionXp,
        );
        next = next.withReplayedDates(
          _replayedDates(
            replay,
            outline.toCourseLoOutline(xpToComplete: xpToComplete),
            course.id,
            awaiting,
          ),
        );
      }
      if (!next.changedSince(stored)) continue;
      await client.setRoomStateWithKey(
        analyticsRoom.id,
        PangeaEventTypes.courseProgress,
        course.id,
        next.toJson(),
      );
      _written[course.id] = next;
    }
  }

  /// When each of [missionIds] first reached [course]'s threshold, replayed
  /// from history. A Mission whose replay finds no such moment is reported
  /// and left undated.
  Map<String, DateTime> _replayedDates(
    MissionCompletionReplay replay,
    CourseLoOutline course,
    String courseRoomId,
    List<String> missionIds,
  ) {
    final dates = <String, DateTime>{};
    for (final missionId in missionIds) {
      final at = replay.firstReached(course, missionId);
      if (at != null) {
        dates[missionId] = at;
        continue;
      }
      // It shows as complete, so some moment of its history reached the
      // threshold; finding none means the replay and the ring disagree.
      _unreplayable.add('$courseRoomId|$missionId');
      ErrorHandler.logErrorOnce(
        key: 'course-progress-replay:$courseRoomId:$missionId',
        e: 'A complete Mission\'s replayed history never reaches its threshold',
        data: {'courseRoomId': courseRoomId, 'missionId': missionId},
        level: SentryLevel.warning,
      );
    }
    return dates;
  }

  /// [course]'s outline as the course shows it, read the way the course page
  /// reads it. Null, and reported, when it can't be read.
  Future<QuestOutline?> _outlineOf(Room course) async {
    final questId = course.coursePlan?.uuid;
    if (questId == null) return null;
    final rules = course.courseListRules;
    final result = await QuestRepo.outline(
      questId,
      courseRoomId: course.id,
      courseLoIds: rules.missions?.allLoIds ?? const {},
      copyRevision: rules.revision,
    );
    final outline = result.result;
    if (outline == null) {
      unawaited(
        reportCourseOutlineFailure(
          course.id,
          questId,
          result.error ?? MissingQuestException(),
          StackTrace.current,
        ),
      );
      return null;
    }
    return outline.forRules(rules);
  }

  /// The record stored for [courseId]: the room's, or what this run wrote
  /// after it when that write hasn't synced back yet.
  CourseProgressEvent? _storedFor(Room analyticsRoom, String courseId) {
    final state = analyticsRoom.getState(
      PangeaEventTypes.courseProgress,
      courseId,
    );
    final synced = state == null
        ? null
        : CourseProgressEvent.fromJson(state.content);
    if (state != null && synced == null) {
      // Its dates can't be read, so they can't be kept; the next write
      // replaces the record.
      ErrorHandler.logErrorOnce(
        key: 'course-progress-unreadable:$courseId',
        e: 'Stored course progress record could not be read',
        data: {'analyticsRoomId': analyticsRoom.id, 'courseRoomId': courseId},
        level: SentryLevel.warning,
      );
    }
    final written = _written[courseId];
    if (written == null) return synced;
    if (synced != null && !synced.computedAt.isBefore(written.computedAt)) {
      _written.remove(courseId);
      return synced;
    }
    return written;
  }

  static Future<String> _appVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.buildNumber.isEmpty
        ? info.version
        : '${info.version}+${info.buildNumber}';
  }
}
