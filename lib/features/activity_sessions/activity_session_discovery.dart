import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';

/// Discovery of activity-session rooms across the learner's joined courses.
///
/// The one shared answer to "which session rooms exist for my courses'
/// activities", used by both the world map's joinable-pin signals and the
/// activity start page's join list — so both resolve it the same way, from the
/// **server** hierarchy and independent of any single course in scope (a bare
/// map pin carries none). See world-map.instructions.md.
extension ActivitySessionDiscovery on Client {
  /// The learner's joined course spaces (a joined space carrying a course plan).
  List<Room> get joinedCourseSpaces => rooms
      .where(
        (r) =>
            r.isSpace &&
            r.membership == Membership.join &&
            r.coursePlan != null,
      )
      .toList();

  /// Session rooms the learner is **invited** to. They sit in `client.rooms`,
  /// but an invite's stripped state carries no `pangea.activity_roles`, so any
  /// seat/participant data read locally is wrong (#7488) — callers must
  /// room_preview these ids, never trust the local room.
  Set<String> get invitedActivitySessionRoomIds => rooms
      .where((r) => r.membership == Membership.invite && r.activityId != null)
      .map((r) => r.id)
      .toSet();

  /// Room ids of activity-session children across [joinedCourseSpaces], read from
  /// the server hierarchy so a coursemate's session (absent from `client.rooms`)
  /// is included. Optionally scoped to a single [activityId] by room type.
  ///
  /// Each course space's hierarchy is **fully paginated** (the same `from`/
  /// `nextBatch` walk the course chats page uses), so a session past the first
  /// 100 rooms in a large course is still found — the #7982 miss. Because this
  /// runs on the world map's hot discovery loop (~every 3s, across *all* joined
  /// courses), the paginated scan of each space is cached for
  /// [_CourseSessionScanCache.ttl]; the per-cycle freshness that must stay live
  /// (seats/presence) comes from the caller's `room_preview` step, not from this
  /// id enumeration, so caching the id set here does not stale the map. The
  /// cache holds the **unscoped** set, so the map (unscoped) and the start page
  /// (scoped to one activity) share a single scan.
  ///
  /// Best-effort per course; a failed hierarchy read is logged and skipped
  /// (its cache entry is left untouched so the next cycle retries).
  Future<Set<String>> courseActivitySessionRoomIds({String? activityId}) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ids = <String>{};
    for (final space in joinedCourseSpaces) {
      var sessions = _CourseSessionScanCache.instance.fresh(space.id, nowMs);
      if (sessions == null) {
        sessions = await paginateActivitySessionRooms(
          spaceId: space.id,
          fetchPage: (from) => getSpaceHierarchy(
            space.id,
            maxDepth: 1,
            from: from,
            limit: 100,
          ),
        );
        if (sessions == null) continue; // failed read — retry next cycle
        _CourseSessionScanCache.instance.store(space.id, sessions, nowMs);
      }
      ids.addAll(activitySessionIdsMatching(sessions, activityId: activityId));
    }
    return ids;
  }
}

/// Room ids from a scanned `{roomId: roomType}` map, optionally scoped to a
/// single [activityId] via the exact `p.activity.session:$activityId` type — so
/// the map (unscoped) and the start page (scoped) filter the one shared,
/// unscoped cached scan differently.
@visibleForTesting
Set<String> activitySessionIdsMatching(
  Map<String, String> sessions, {
  String? activityId,
}) {
  if (activityId == null) return sessions.keys.toSet();
  final exactType = '${PangeaRoomTypes.activitySession}:$activityId';
  return sessions.entries
      .where((e) => e.value == exactType)
      .map((e) => e.key)
      .toSet();
}

/// A generous safety bound on the paginated scan of one course space's
/// hierarchy (~[_maxHierarchyPagesPerSpace] * 100 rooms). Hitting it is logged
/// rather than silently truncating — a course this large is beyond what
/// client-side discovery can cover and wants the deferred choreographer
/// cross-course endpoint (world-map.instructions.md "Future Work").
const int _maxHierarchyPagesPerSpace = 20;

/// Walk one space's hierarchy to completion, returning its activity-session
/// rooms as `{roomId: roomType}` (unscoped). [fetchPage] is the paginated
/// hierarchy read — injected so the pagination/cap/error logic is testable
/// without a live client. Returns `null` on a failed read (logged) so the
/// caller leaves any cached entry in place and retries; a successful scan of a
/// space with no sessions returns an empty map.
@visibleForTesting
Future<Map<String, String>?> paginateActivitySessionRooms({
  required String spaceId,
  required Future<GetSpaceHierarchyResponse> Function(String? from) fetchPage,
  int maxCalls = _maxHierarchyPagesPerSpace,
}) async {
  final found = <String, String>{};
  String? from;
  var calls = 0;
  try {
    do {
      final page = await fetchPage(from);
      for (final child in page.rooms) {
        if (child.roomId == spaceId) continue; // the space root itself
        final type = child.roomType;
        if (type == null ||
            !type.startsWith(PangeaRoomTypes.activitySession)) {
          continue; // only activity-session rooms
        }
        found[child.roomId] = type;
      }
      from = page.nextBatch;
      calls++;
    } while (from != null && calls < maxCalls);
    if (from != null) {
      // More pages remain but we've hit the cap — log so a pathologically large
      // course is visible rather than a silent partial scan.
      ErrorHandler.logError(
        e: Exception('activity-session hierarchy scan hit page cap'),
        m: 'activity-session discovery truncated for large course space',
        data: {'spaceId': spaceId, 'calls': calls},
      );
    }
    return found;
  } catch (e, s) {
    ErrorHandler.logError(
      e: e,
      s: s,
      m: 'course space hierarchy fetch failed',
      data: {'spaceId': spaceId},
    );
    return null;
  }
}

/// Per-space cache of the fully-paginated activity-session room scan, so the
/// world map's ~3s discovery loop reuses one hierarchy walk per course for
/// [ttl] instead of re-paging every cycle. Freshness of seats/presence is the
/// caller's per-cycle `room_preview` job, not this id set (which only changes
/// when a session opens/closes), so a short TTL keeps the map current while
/// bounding request volume. Process-wide singleton, like DiscoveredSessionsCache.
class _CourseSessionScanCache {
  _CourseSessionScanCache._();
  static final _CourseSessionScanCache instance = _CourseSessionScanCache._();

  /// Well inside #7982's "after 1-2 minutes" expectation given the ~3s loop.
  static const Duration ttl = Duration(seconds: 30);

  final Map<String, _ScanEntry> _bySpace = {};

  /// The cached scan for [spaceId] (`{roomId: roomType}`) if it is still within
  /// [ttl] at [nowMs], else null (the caller re-scans).
  Map<String, String>? fresh(String spaceId, int nowMs) {
    final entry = _bySpace[spaceId];
    if (entry == null) return null;
    if (nowMs - entry.scannedAtMs > ttl.inMilliseconds) return null;
    return entry.sessions;
  }

  void store(String spaceId, Map<String, String> sessions, int nowMs) {
    _bySpace[spaceId] = _ScanEntry(sessions, nowMs);
  }

  void clear() => _bySpace.clear();
}

class _ScanEntry {
  _ScanEntry(this.sessions, this.scannedAtMs);
  final Map<String, String> sessions;
  final int scannedAtMs;
}

/// Test seams onto the process-wide scan cache. The singleton persists across
/// tests, so a suite resets it in `setUp`; the store/fresh wrappers exercise the
/// TTL logic deterministically with an injected `nowMs` (no real clock).
@visibleForTesting
void debugResetActivitySessionScanCache() =>
    _CourseSessionScanCache.instance.clear();

@visibleForTesting
Map<String, String>? debugFreshActivitySessionScan(String spaceId, int nowMs) =>
    _CourseSessionScanCache.instance.fresh(spaceId, nowMs);

@visibleForTesting
void debugStoreActivitySessionScan(
  String spaceId,
  Map<String, String> sessions,
  int nowMs,
) =>
    _CourseSessionScanCache.instance.store(spaceId, sessions, nowMs);

@visibleForTesting
Duration get debugActivitySessionScanTtl => _CourseSessionScanCache.ttl;
