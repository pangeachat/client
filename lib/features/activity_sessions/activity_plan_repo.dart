import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' show Response;
import 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;

import 'package:fluffychat/features/activity_sessions/activity_media_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_fetch_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_fetch_response.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/persistent_repo_cache.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// How a plan [ActivityPlanRepo.lookup] resolved.
enum ActivityPlanLookupStatus {
  /// The plan was fetched, or served from the cache.
  found,

  /// The backend confirmed the activity no longer exists (HTTP 404).
  /// Consumers fall back per the removed-activity ladder in the activities
  /// instructions doc (embedded state plan → archived view).
  removed,

  /// Transient failure (network, timeout, 5xx); retrying may succeed. Never
  /// treated as "removed", so an outage can't mislabel healthy activities.
  failed,
}

class ActivityPlanLookup {
  final ActivityPlanLookupStatus status;
  final ActivityPlanModel? plan;

  const ActivityPlanLookup(this.status, [this.plan]);
}

/// The single cached read path for activity plans.
///
/// Extends [BaseRepo] (TTL + in-flight dedup + synchronous `getCached`) over
/// the choreographer `GET /v2/activity` endpoint, so every caller — the
/// in-room `room.activityPlan` getter, the start page, the world map — shares
/// one cache instead of hitting the backend independently.
///
/// Two layers:
///  - [BaseRepo] persists the **raw** [ActivityPlanFetchResponse] (stable
///    `upload_id`s) to disk with a TTL.
///  - an in-memory [_resolved] map holds the media-RESOLVED
///    [ActivityPlanModel] (CDN urls, session-scoped, never persisted) so a
///    resolved plan can be returned synchronously.
///
/// Reactivity (the [ChangeNotifier] mixin) lives only on this subclass, not in
/// [BaseRepo]: `room.activityPlan` is a *synchronous* getter read by many
/// widgets, so they wrap in a `ListenableBuilder` on [instance] to rebuild when
/// a plan lands. No other repo feeds a sync getter, so the base stays plain.
class ActivityPlanRepo
    extends BaseRepo<ActivityPlanFetchRequest, ActivityPlanFetchResponse>
    with ChangeNotifier {
  ActivityPlanRepo._internal()
    : super(
        cache: PersistentRepoCache<ActivityPlanFetchResponse>(
          'activity_plan_storage',
        ),
        responseFromJson: ActivityPlanFetchResponse.fromJson,
        cacheDuration: const Duration(hours: 1),
      );

  static final ActivityPlanRepo _instance = ActivityPlanRepo._internal();
  static ActivityPlanRepo get instance => _instance;

  final Map<String, ActivityPlanModel> _resolved = {};
  final Set<String> _hydrating = {};
  final Set<String> _revalidated = {};

  /// Activity ids the backend confirmed removed (404) this app session, so
  /// [ensure] stops re-fetching a known-missing id on every widget rebuild.
  final Set<String> _confirmedRemoved = {};

  @override
  Future<Response> fetch(Requests req, ActivityPlanFetchRequest request) {
    final uri = Uri.parse(PApiUrls.activityById(request.activityId)).replace(
      queryParameters: {
        if (request.l1.isNotEmpty) 'l1': request.l1,
        // The session's pinned content-signature; omitted for discovery reads,
        // which want the latest.
        if (request.version != null) 'version': request.version!,
      },
    );
    return req.get(url: uri.toString());
  }

  String get _viewerL1 =>
      MatrixState.pangeaController.userController.userL1Code ?? 'en';

  ActivityPlanFetchRequest _request(
    String activityId,
    String? l1, {
    String? version,
  }) => ActivityPlanFetchRequest(
    activityId: activityId,
    l1: l1 ?? _viewerL1,
    version: version,
  );

  /// The plan for [activityId], localized to [l1] (viewer L1 by default), with
  /// media resolved. Cached (TTL + in-flight dedup); null on fetch failure.
  /// [forceRefresh] re-fetches past the TTL (the cache survives until the fresh
  /// plan lands). Callers that need to tell a removed activity apart from a
  /// transient failure use [lookup].
  Future<ActivityPlanModel?> getPlan(
    String activityId, {
    String? l1,
    String? version,
    bool forceRefresh = false,
  }) async {
    final result = await lookup(
      activityId,
      l1: l1,
      version: version,
      forceRefresh: forceRefresh,
    );
    return result.plan;
  }

  /// [getPlan] with the failure kind surfaced: [ActivityPlanLookupStatus
  /// .removed] on a confirmed 404 vs [ActivityPlanLookupStatus.failed] on a
  /// transient error.
  Future<ActivityPlanLookup> lookup(
    String activityId, {
    String? l1,
    String? version,
    bool forceRefresh = false,
  }) async {
    final request = _request(activityId, l1, version: version);
    final result = await get(request, forceRefresh: forceRefresh);
    if (result.isError) {
      final status = classifyLookupError(result.asError!.error);
      if (status == ActivityPlanLookupStatus.removed) {
        _confirmedRemoved.add(activityId);
      }
      return ActivityPlanLookup(status);
    }

    _confirmedRemoved.remove(activityId);
    final resolved = await resolveMedia(result.asValue!.value.plan);
    _resolved[request.storageKey] = resolved;
    notifyListeners();
    return ActivityPlanLookup(ActivityPlanLookupStatus.found, resolved);
  }

  @visibleForTesting
  static ActivityPlanLookupStatus classifyLookupError(Object error) =>
      error is Response && error.statusCode == 404
      ? ActivityPlanLookupStatus.removed
      : ActivityPlanLookupStatus.failed;

  /// Synchronous lookup for `room.activityPlan`: the media-resolved plan if
  /// [getPlan] has run, else the raw (TTL-checked) cached plan, else null — in
  /// which case the caller should [ensure]. Drops the resolved entry when the
  /// underlying TTL'd cache has expired so it can't outlive it.
  ActivityPlanModel? cachedPlan(
    String activityId, {
    String? l1,
    String? version,
  }) {
    final request = _request(activityId, l1, version: version);
    final raw = getCached(request);
    if (raw == null) {
      _resolved.remove(request.storageKey);
      return null;
    }
    return _resolved[request.storageKey] ?? raw.plan;
  }

  /// Fire-and-forget hydration for the synchronous getter. No-op when a
  /// resolved plan is present or a fetch is already in flight.
  ///
  /// [revalidate] re-fetches the latest localized plan once per (activity, l1)
  /// per app session, even if a cached plan exists. The cache keys on the
  /// canonical version, which a re-translation does NOT bump, so without this a
  /// localized-content change (re-translation / cascade) never reaches a client
  /// holding a cached plan until the TTL lapses. Used on session open so the
  /// learner sees current goal text / role names; the world map intentionally
  /// does NOT revalidate (one fetch per visible pin would be a fetch storm).
  /// Stale-while-revalidate: [cachedPlan] keeps serving the old plan until the
  /// fresh one lands, so there is no loading flicker.
  void ensure(
    String activityId, {
    String? l1,
    String? version,
    bool revalidate = false,
  }) {
    // A confirmed-removed id can't hydrate; re-fetching on every rebuild of
    // the sync getter would loop 404s.
    if (_confirmedRemoved.contains(activityId)) return;
    final key = _request(activityId, l1, version: version).storageKey;
    if (_hydrating.contains(key)) return;
    final doRevalidate = revalidate && _revalidated.add(key);
    if (!doRevalidate && _resolved.containsKey(key)) return;
    _hydrating.add(key);
    getPlan(
      activityId,
      l1: l1,
      version: version,
      forceRefresh: doRevalidate,
    ).whenComplete(() => _hydrating.remove(key));
  }

  /// Resolves upload-referenced media blocks to CDN urls. Applied to every
  /// fetched plan, and by fallback consumers to legacy plans read from room
  /// state (which carry the same unresolved `upload_id` references).
  ///
  /// Fail-soft: a resolution failure (e.g. the CMS media read erroring)
  /// returns the plan with its blocks unresolved, and they degrade to the
  /// placeholder render. Media must never take down the plan itself — before
  /// this guard a CMS 403 surfaced as "Activity not found" on a perfectly
  /// healthy activity.
  Future<ActivityPlanModel> resolveMedia(ActivityPlanModel plan) async {
    final ids = plan.media
        .map((b) => b.uploadId)
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return plan;
    final Map<String, ResolvedMedia> resolved;
    try {
      resolved = await ActivityMediaRepo.resolve(ids);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"activityId": plan.activityId},
        level: SentryLevel.warning,
      );
      return plan;
    }
    return plan.withMedia(
      plan.media.map((block) {
        final r = block.uploadId == null ? null : resolved[block.uploadId];
        return r == null
            ? block
            : block.copyWithResolved(
                resolvedUrl: r.url,
                resolvedThumbnailUrl: r.thumbnailUrl,
                resolvedMediumUrl: r.mediumUrl,
              );
      }).toList(),
    );
  }
}
