import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' show Response;
import 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;

import 'package:fluffychat/features/activity_sessions/activity_media_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_fetch_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_fetch_response.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
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

  /// Earliest wall-clock time [ensure] may re-attempt a key.
  ///
  /// Set **before** the fetch is issued, and cleared only on success. That
  /// ordering is the whole point: the previous guards (`_confirmedRemoved`,
  /// `_hydrating`, `_resolved`) each recorded a specific *outcome*, so any
  /// outcome nobody had enumerated — a 429, a 5xx, a mapping throw — matched
  /// none of them and re-fetched on the very next rebuild. [ensure] is reached
  /// from `build()`, so "no guard matched" meant "re-fetch at frame rate".
  /// Parking on the *attempt* is total over outcomes that do not exist yet.
  ///
  /// Staging 2026-08-04: a 429 returns in ~47ms against ~5s for a success, so
  /// the unguarded path turned ~1 fetch/5s into ~20/sec per card — the throttle
  /// *increased* load ~100x and kept the per-user budget exhausted for hours.
  final Map<String, DateTime> _nextAttempt = {};

  /// Repo-wide pause after the backend rate-limits us.
  ///
  /// [_nextAttempt] is per key, and the number of keys is unbounded (the world
  /// map hydrates one per visible pin — 104 distinct ids during the incident).
  /// K keys under a per-key cooldown still emit K/cooldown requests, which at
  /// K=104 exceeds the 60/min budget on its own. Only a repo-wide pause
  /// restores the invariant "we stop when the server says stop", independent
  /// of K. Deliberately scoped to this repo rather than shared: choreo budgets
  /// `/choreo` and `/subscription` separately, so an activity 429 must never
  /// stall checkout.
  DateTime? _rateLimitedUntil;

  static const Duration _attemptCooldown = Duration(seconds: 60);
  static const Duration _rateLimitPause = Duration(seconds: 60);

  /// Test seam: [ensure]'s clock. Backoff is wall-clock, so tests would
  /// otherwise need real delays.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// Drops all backoff state. Exposed for tests and for an explicit
  /// user-initiated refresh, which must never be suppressed.
  @visibleForTesting
  void resetBackoff() {
    _nextAttempt.clear();
    _rateLimitedUntil = null;
  }

  /// Test seam: simulate the repo having just been rate-limited, without
  /// needing a live 429 from the network layer.
  @visibleForTesting
  void rateLimitedForTesting(Duration pause) =>
      _rateLimitedUntil = now().add(pause);

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
      final error = result.asError!.error;
      // A 429 is a statement about RATE, not about this key, so it pauses the
      // whole repo. Per-key backoff alone cannot honour it: the map hydrates
      // one key per visible pin, and K keys each backing off independently
      // still emit K/cooldown requests.
      if (PangeaHttpException.statusCodeOf(error) == 429) {
        _rateLimitedUntil = now().add(_rateLimitPause);
      }
      final status = classifyLookupError(error);
      if (status == ActivityPlanLookupStatus.removed) {
        _confirmedRemoved.add(activityId);
      }
      return ActivityPlanLookup(status);
    }

    _confirmedRemoved.remove(activityId);
    final resolved = await resolveMedia(result.asValue!.value.plan);
    _resolved[request.storageKey] = resolved;
    // Cleared only on a fully-mapped success. `.plan` above is a lazy getter
    // that runs the whole v2 mapping, so a malformed body throws HERE, after a
    // perfectly good HTTP 200 — leaving the parked entry in place, which is
    // exactly what we want.
    _nextAttempt.remove(request.storageKey);
    notifyListeners();
    return ActivityPlanLookup(ActivityPlanLookupStatus.found, resolved);
  }

  /// Refuse to memoize a body whose mapping throws.
  ///
  /// `ActivityPlanFetchResponse.plan` is a LAZY getter, so `BaseRepo.get`
  /// writes to disk before anything has tried to map it. A malformed body
  /// would therefore be persisted for the full TTL and then re-thrown on every
  /// frame by [cachedPlan], which is called synchronously from `build()`.
  /// Mapping once here turns that into an ordinary cache miss — which the
  /// attempt cooldown then bounds. Same policy hook, and same reasoning, as
  /// `SpeechToTextRepo` refusing to cache an exhausted-fallback response.
  @override
  bool shouldCache(ActivityPlanFetchResponse response) {
    try {
      response.plan;
      return true;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static ActivityPlanLookupStatus classifyLookupError(Object error) =>
      PangeaHttpException.statusCodeOf(error) == 404
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
  /// Returns whether this call actually issued a fetch. Callers may ignore it;
  /// it exists so the suppression policy is observable without reaching into
  /// private state.
  bool ensure(
    String activityId, {
    String? l1,
    String? version,
    bool revalidate = false,
  }) {
    // A confirmed-removed id can't hydrate; re-fetching on every rebuild of
    // the sync getter would loop 404s.
    if (_confirmedRemoved.contains(activityId)) return false;
    final key = _request(activityId, l1, version: version).storageKey;
    // Checked before `_revalidated.add` so a revalidate token is never spent
    // on a call that is about to bail.
    if (_hydrating.contains(key)) return false;
    final doRevalidate = revalidate && _revalidated.add(key);
    if (!doRevalidate) {
      if (_resolved.containsKey(key)) return false;
      final at = now();
      final pausedUntil = _rateLimitedUntil;
      if (pausedUntil != null) {
        if (at.isBefore(pausedUntil)) return false;
        _rateLimitedUntil = null;
      }
      final retryAt = _nextAttempt[key];
      if (retryAt != null && at.isBefore(retryAt)) return false;
    }
    // PARK BEFORE THE I/O, not after it resolves. Every failure mode — 429,
    // 5xx, network, timeout, a `.plan` mapping throw, and anything added
    // later — is covered by this single line, because it does not depend on
    // classifying the outcome. This is the guard the three outcome-keyed sets
    // above could never be.
    _nextAttempt[key] = now().add(_attemptCooldown);
    _hydrating.add(key);
    getPlan(activityId, l1: l1, version: version, forceRefresh: doRevalidate)
        .catchError((Object e, StackTrace s) {
          // `getPlan` is fire-and-forget here, and `.plan`'s mapping runs outside
          // BaseRepo's try/catch, so without this a malformed body is an unhandled
          // async error. The parked entry stays put, so it cannot re-arm.
          ErrorHandler.logError(
            e: e,
            s: s,
            data: {'activityId': activityId, 'l1': l1, 'version': version},
            level: SentryLevel.warning,
          );
          return null;
        })
        .whenComplete(() => _hydrating.remove(key));
    return true;
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
