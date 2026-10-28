import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/course_language_scope.dart';
import 'package:fluffychat/features/quests/course_progress_event.dart';
import 'package:fluffychat/features/quests/course_progress_room_extension.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/mission_completion_replay.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
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

  /// Course and Mission pairs whose replay found no date this run, so a
  /// failing replay isn't repeated after every upload.
  final Set<String> _unreplayable = {};

  /// How long a course's outline read may take before the check skips the
  /// course: the read goes over the network.
  static const _outlineReadTimeout = Duration(seconds: 5);

  /// How long a course whose outline read failed is skipped, so a failing
  /// read is retried at this pace rather than on every check.
  static const _outlineRetryAfter = Duration(minutes: 10);

  /// When each course whose outline read last failed may be read again.
  final Map<String, DateTime> _outlineRetryAt = {};

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
    // The records aren't loaded with the room at startup, since only the
    // learner's own app reads them; read the room's state in full first, or
    // a stored completion date would be missed and overwritten.
    if (analyticsRoom.partial) await analyticsRoom.postLoad();
    final xpByActivity = client.userXpByActivity(cache.creditedXpByRoom);
    final byActivity = client.cachedXpBreakdownByActivity;
    final appVersion = await _appVersion();
    MissionCompletionReplay? replay;
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
          recorded: stored?.canDos ?? const {},
        ),
        now: DateTime.now().toUtc(),
        appVersion: appVersion,
      );
      final awaiting = [
        for (final missionId in next.awaitingReplay)
          if (!_unreplayable.contains('${course.id}|$missionId')) missionId,
      ];
      if (awaiting.isNotEmpty) {
        final history = replay ??= MissionCompletionReplay(
          uses: await _readUses(language),
          sessions: client.savedSessionXp,
        );
        next = next.withReplayedDates(
          await _replayedDates(
            history,
            outline.toCourseLoOutline(xpToComplete: xpToComplete),
            course.id,
            awaiting,
          ),
        );
      }
      if (!next.changedSince(stored)) continue;
      await analyticsRoom.setCourseProgress(course.id, next);
      _written[course.id] = next;
    }
  }

  /// When each of [missionIds] first reached [course]'s threshold, replayed
  /// from history, one Mission at a time with a frame let through between
  /// them. A Mission whose replay finds no such moment is reported and left
  /// undated.
  Future<Map<String, DateTime>> _replayedDates(
    MissionCompletionReplay replay,
    CourseLoOutline course,
    String courseRoomId,
    List<String> missionIds,
  ) async {
    final dates = <String, DateTime>{};
    for (final missionId in missionIds) {
      await Future<void>.delayed(Duration.zero);
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
  /// reads it. Null when it can't be read in time, which is reported, or
  /// while a failed read waits to be retried.
  Future<QuestOutline?> _outlineOf(Room course) async {
    final questId = course.coursePlan?.uuid;
    if (questId == null) return null;
    final retryAt = _outlineRetryAt[course.id];
    if (retryAt != null && DateTime.now().isBefore(retryAt)) return null;
    final rules = course.courseListRules;
    final QuestOutline? outline;
    final Object? error;
    try {
      final result = await QuestRepo.outline(
        questId,
        courseRoomId: course.id,
        courseLoIds: rules.missions?.allLoIds ?? const {},
        copyRevision: rules.revision,
      ).timeout(_outlineReadTimeout);
      outline = result.result;
      error = result.error;
    } on TimeoutException catch (e, s) {
      _outlineFailed(course.id, questId, e, s);
      return null;
    }
    if (outline == null) {
      _outlineFailed(
        course.id,
        questId,
        error ?? MissingQuestException(),
        StackTrace.current,
      );
      return null;
    }
    _outlineRetryAt.remove(course.id);
    return outline.forRules(rules);
  }

  /// Reports [courseRoomId]'s failed outline read and skips the course until
  /// [_outlineRetryAfter] has passed.
  void _outlineFailed(
    String courseRoomId,
    String questId,
    Object error,
    StackTrace stack,
  ) {
    _outlineRetryAt[courseRoomId] = DateTime.now().add(_outlineRetryAfter);
    unawaited(reportCourseOutlineFailure(courseRoomId, questId, error, stack));
  }

  /// The record stored for [courseId]: the room's, or what this run wrote
  /// after it when that write hasn't synced back yet.
  CourseProgressEvent? _storedFor(Room analyticsRoom, String courseId) {
    final synced = analyticsRoom.courseProgress(courseId);
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
