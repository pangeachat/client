import 'dart:convert';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';

extension ActivityLockClientExtension on Client {
  /// The course rooms whose progression keeps [activityId] from being
  /// started — empty when it is unlocked — by the same resolver the map and
  /// course panel use. Stars and the teacher flag are read fresh on every
  /// call. With [courseId] (launched from a course), only that course's locks
  /// count.
  Future<List<Room>> coursesLockingActivity(
    String activityId, {
    String? courseId,
  }) async {
    final cache = await _ActivityLockOutlines.of(this).current();
    return [
      for (final id
          in cache
              .resolution(userStarsByActivity)
              .coursesLocking(activityId, courseId: courseId))
        ?getRoomById(id),
    ];
  }

  Future<bool> isActivityLocked(String activityId, {String? courseId}) async =>
      (await coursesLockingActivity(activityId, courseId: courseId)).isNotEmpty;

  /// Whether [update] can change a lock: stars or seats on a session room,
  /// or a course's teacher flag or settings. Anything else (messages, typing,
  /// other rooms' chatter) leaves every lock as it was.
  static bool syncAffectsLocks(SyncUpdate update) {
    final joined = update.rooms?.join;
    if (joined == null) return false;
    for (final room in joined.values) {
      final events = [...?room.state, ...?room.timeline?.events];
      if (events.any((e) => _lockEventTypes.contains(e.type))) return true;
    }
    return false;
  }

  static const Set<String> _lockEventTypes = {
    PangeaEventTypes.orchestratorAwardedGoals,
    PangeaEventTypes.activityRole,
    PangeaEventTypes.courseTeacher,
    PangeaEventTypes.teacherMode,
    PangeaEventTypes.coursePlan,
  };
}

/// One client's joined-course outlines for lock checks, rebuilt only when the
/// set of joined courses or their teacher settings change, or — after a
/// course failed to load — once [_retryAfterFailure] has passed.
class _ActivityLockOutlines {
  static final Expando<_ActivityLockOutlines> _byClient = Expando();

  static _ActivityLockOutlines of(Client client) =>
      _byClient[client] ??= _ActivityLockOutlines(client);

  static const Duration _retryAfterFailure = Duration(minutes: 1);

  final Client client;
  final JoinedObjectiveCache _cache = JoinedObjectiveCache();
  String? _signature;
  DateTime? _failedAt;
  Future<void>? _rebuilding;

  _ActivityLockOutlines(this.client);

  /// What the outlines were built from: each joined course, its plan and its
  /// teacher settings (threshold and pins).
  String get _currentSignature => jsonEncode([
    for (final room in client.joinedCourseRooms)
      [room.id, room.coursePlan?.uuid, room.teacherMode.toJson()],
  ]);

  Future<JoinedObjectiveCache> current() async {
    final signature = _currentSignature;
    final failedAt = _failedAt;
    final retryDue =
        failedAt != null &&
        DateTime.now().difference(failedAt) > _retryAfterFailure;
    if (signature != _signature || retryDue) {
      await (_rebuilding ??= _rebuild(signature));
    }
    return _cache;
  }

  Future<void> _rebuild(String signature) async {
    var failed = false;
    try {
      await _cache.rebuildFromJoinedCourses(
        client,
        onError: (roomId, questId, e, s) {
          failed = true;
          reportCourseOutlineFailure(roomId, questId, e, s);
        },
      );
      _signature = signature;
      _failedAt = failed ? DateTime.now() : null;
    } finally {
      _rebuilding = null;
    }
  }
}
