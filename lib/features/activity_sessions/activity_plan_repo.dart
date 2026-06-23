import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' show Response;

import 'package:fluffychat/features/activity_sessions/activity_media_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_fetch_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_fetch_response.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

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
        boxName: 'activity_plan_storage',
        responseFromJson: ActivityPlanFetchResponse.fromJson,
        cacheDuration: const Duration(hours: 1),
      );

  static final ActivityPlanRepo _instance = ActivityPlanRepo._internal();
  static ActivityPlanRepo get instance => _instance;

  final Map<String, ActivityPlanModel> _resolved = {};
  final Set<String> _hydrating = {};
  final Set<String> _revalidated = {};

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
  /// plan lands).
  Future<ActivityPlanModel?> getPlan(
    String activityId, {
    String? l1,
    String? version,
    bool forceRefresh = false,
  }) async {
    final request = _request(activityId, l1, version: version);
    final result = await get(request, forceRefresh: forceRefresh);
    final response = result.result;
    if (response == null) return null;

    final resolved = await _withResolvedMedia(response.plan);
    _resolved[request.storageKey] = resolved;
    notifyListeners();
    return resolved;
  }

  /// Synchronous lookup for `room.activityPlan`: the media-resolved plan if
  /// [getPlan] has run, else the raw (TTL-checked) cached plan, else null — in
  /// which case the caller should [ensure]. Drops the resolved entry when the
  /// underlying TTL'd cache has expired so it can't outlive it.
  ActivityPlanModel? cachedPlan(String activityId, {String? l1, String? version}) {
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

  Future<ActivityPlanModel> _withResolvedMedia(ActivityPlanModel plan) async {
    final ids = plan.media
        .map((b) => b.uploadId)
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return plan;
    final resolved = await ActivityMediaRepo.resolve(ids);
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
