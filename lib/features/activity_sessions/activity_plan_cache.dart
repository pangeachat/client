import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Hydrates `pangea.activity_plan` room-state *references* into full
/// [ActivityPlanModel]s, in memory, for the app session.
///
/// A v3 session room stores only `{ activity_id, version_id }`; the plan body
/// stays canonical in CMS. The synchronous `room.activityPlan` getter can't
/// fetch, so it reads from here and kicks off [ensure]. This is a
/// [ChangeNotifier]: the activity surfaces wrap in a `ListenableBuilder` on
/// [instance] so they rebuild when a plan lands (a sync event is not guaranteed
/// to coincide with hydration).
///
/// The fetch is delegated to [QuestRepo.activity] — the single activity read
/// path, which already maps and resolves media. When that read swaps to the
/// choreographer's localized GET, this cache benefits with no change here.
///
/// Version pinning: the room pins `version_id`, but [QuestRepo.activity] reads
/// the canonical (latest) row — version-pinned reads are a cross-repo follow-up
/// (the choreographer currently ignores `?version=` too). Tracked in the org
/// activities doc as a future enhancement.
class ActivityPlanCache extends ChangeNotifier {
  ActivityPlanCache._();
  static final ActivityPlanCache instance = ActivityPlanCache._();

  final Map<String, ActivityPlanModel> _byActivityId = {};
  final Set<String> _missing = {};
  final Map<String, Future<ActivityPlanModel?>> _pending = {};
  final Map<String, DateTime> _failedAt = {};

  /// Back-off between retries after a transient (network) failure, so a tight
  /// rebuild loop can't hammer the backend.
  static const Duration _retryCooldown = Duration(seconds: 10);

  /// The hydrated plan for [activityId], or null if not yet fetched.
  ActivityPlanModel? cached(String activityId) => _byActivityId[activityId];

  /// Fire-and-forget hydration for the synchronous `room.activityPlan` getter.
  /// No-op when cached, in flight, confirmed missing, or within the post-failure
  /// cool-down.
  void ensure(String activityId) {
    if (_byActivityId.containsKey(activityId) ||
        _missing.contains(activityId) ||
        _pending.containsKey(activityId)) {
      return;
    }
    final failedAt = _failedAt[activityId];
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < _retryCooldown) {
      return;
    }
    unawaited(hydrate(activityId));
  }

  /// Awaitable hydration — returns the plan (cached or freshly fetched), or
  /// null when there is no canonical row / the fetch failed. Concurrent calls
  /// for the same id share one in-flight fetch. Use when a flow needs the plan
  /// now (e.g. the end-of-session summary), not just opportunistically.
  Future<ActivityPlanModel?> hydrate(String activityId) {
    final existing = _byActivityId[activityId];
    if (existing != null) return Future.value(existing);
    return _pending.putIfAbsent(activityId, () => _fetch(activityId));
  }

  Future<ActivityPlanModel?> _fetch(String activityId) async {
    try {
      final plan = await QuestRepo.activity(activityId);
      if (plan == null) {
        _missing.add(activityId); // confirmed: no canonical row
        return null;
      }
      _byActivityId[activityId] = plan;
      _missing.remove(activityId);
      _failedAt.remove(activityId);
      notifyListeners();
      return plan;
    } catch (e, s) {
      // Transient (network); retryable after the cool-down, not a confirmed
      // miss. Logged so a persistent failure is observable.
      _failedAt[activityId] = DateTime.now();
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'activityId': activityId, 'op': 'hydrateActivityPlan'},
      );
      return null;
    } finally {
      _pending.remove(activityId);
    }
  }

  /// Drop confirmed-missing / failure markers so the next read retries (e.g.
  /// after the canonical row is created). Cached plans are left intact.
  void invalidateMissing(String activityId) {
    _missing.remove(activityId);
    _failedAt.remove(activityId);
  }
}
