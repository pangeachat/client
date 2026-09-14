import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' show Response;
import 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;

import 'package:fluffychat/features/activity_sessions/activity_media_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_batch.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_fetch_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_fetch_response.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/rate_limit_pause.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/confirmed_removed_cache.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/persistent_repo_cache.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// One hydration waiting for a slot: the key that identifies it in the repo's
/// suppression state, plus what the read needs.
typedef _QueuedHydration = ({
  String activityId,
  String? l1,
  String? version,
  String key,
  bool forceRefresh,
});

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

  /// The failure behind a [ActivityPlanLookupStatus.failed] lookup, so a
  /// display surface can tell a throttle (429 — "wait a moment") from other
  /// transient failures ("check your connection") (#8705). Null when the
  /// lookup never produced an error: found, a persisted removed verdict, or
  /// declined because the controller isn't up yet.
  final Object? error;

  const ActivityPlanLookup(this.status, [this.plan, this.error]);
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
        cache: PersistentRepoCache<ActivityPlanFetchResponse>(_storageBoxName),
        responseFromJson: ActivityPlanFetchResponse.fromJson,
        cacheDuration: const Duration(hours: 1),
      );

  /// A fresh instance over the same persisted storage — the next app session,
  /// for tests. Production code uses [instance] only.
  @visibleForTesting
  ActivityPlanRepo.forTesting() : this._internal();

  static final ActivityPlanRepo _instance = ActivityPlanRepo._internal();
  static ActivityPlanRepo get instance => _instance;

  static const String _storageBoxName = 'activity_plan_storage';

  final Map<String, ActivityPlanModel> _resolved = {};
  final Set<String> _hydrating = {};
  final Set<String> _revalidated = {};

  /// Activity ids the backend confirmed removed (404), so the repo stops
  /// re-fetching a known-missing id.
  ///
  /// Enforced in [lookup], the shared read path — NOT only in [ensure], which
  /// is where this gate first lived. [getPlan] delegates to [lookup] and
  /// [ensure] calls [getPlan], so gating there is what makes the suppression
  /// total over entry points; gating only in [ensure] left the start page and
  /// the summary read re-requesting a gone activity for as long as the surface
  /// stayed open (Sentry CLIENT-DWH: 753 events / 9 users in 24h, all for a
  /// single activity id). Keyed by activity id, not by storage key: the
  /// activity is gone, so no l1 or pinned version of it can resolve either.
  ///
  /// PERSISTED across sessions ([ConfirmedRemovedCache]): in-session
  /// suppression alone left every NEW session re-fetching — and re-reporting —
  /// every known-dead id once, which at ~20 dead ids was still ~120 Sentry
  /// events/day across a handful of users (CLIENT-EB0, #8691). The verdicts
  /// live beside the plan entries in the same box: plan storage keys are
  /// `${activityId}_${l1}_${version}` (uuids in practice), so the reserved
  /// underscored key cannot collide.
  final ConfirmedRemovedCache _confirmedRemoved = ConfirmedRemovedCache(
    boxName: _storageBoxName,
    storageKey: '__confirmed_removed_ids__',
    retention: const Duration(hours: 24),
    now: () => ActivityPlanRepo.now(),
  );

  /// Whether the backend has confirmed [activityId] gone — this session, or a
  /// prior one within the retention window. For callers outside this repo's
  /// read path (`QuestRepo.activityLearningObjectiveRefs`) that would
  /// otherwise re-fetch a known-dead id.
  Future<bool> isConfirmedRemoved(String activityId) =>
      _confirmedRemoved.contains(activityId);

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
  /// K=104 exceeds the budget on its own. Only a repo-wide pause restores the
  /// invariant "we stop when the server says stop", independent of K.
  ///
  /// Its own instance, not a shared one: choreo meters the activity reads and
  /// the subscription surface on separate budgets, so an activity 429 must
  /// never stall checkout. This repo grew the mechanism first (#8160) and kept
  /// it inline; it now uses the shared [RateLimitPause] that was extracted
  /// from it, so the two cannot drift — notably over how long to wait, which
  /// is now the server's `Retry-After` rather than either one's guess.
  RateLimitPause get _rateLimitPause => RateLimitPause.choreoReads;

  static const Duration _attemptCooldown = Duration(seconds: 60);

  /// Ceiling on hydrations in flight at once.
  ///
  /// Staging 2026-08-14: 18 reads left in 30ms and 11 more in 4ms, spending the
  /// whole per-user `/choreo/*` minute budget in one frame and starving the next
  /// unrelated call — `/choreo/tokenize`, which backs free message rendering.
  ///
  /// No backoff can prevent that, and [_rateLimitPause] is not a counter-
  /// example: every guard in [ensure] is temporal or outcome-keyed, so on a COLD
  /// view all of them are empty BY DEFINITION. Nothing has resolved, nothing has
  /// been attempted, and no pause can be armed because no response has come back
  /// yet. [ensure] is reached from `build()`, so K cards in one frame means K
  /// synchronous passes that each clear every guard. Backoff reacts to a
  /// response; the first wave happens before any response exists. Only a bound
  /// on CONCURRENCY closes that, which is why this is a separate mechanism
  /// rather than another cooldown.
  ///
  /// Counted in ACTIVITIES, not requests. Each activity in a batch costs the
  /// learner's allowance exactly what it would have cost alone, so bounding
  /// batches instead would bound nothing that matters: six batches of
  /// [_maxBatchSize] is 300 activities from one frame, well past the whole
  /// minute's allowance — the bound would read as tighter than the original
  /// per-read one while being fifty times looser.
  ///
  /// One full batch at a time. A screen still travels as one request, and a
  /// view larger than a batch drains over successive turns rather than in a
  /// single frame.
  static const int _maxInFlight = _maxBatchSize;

  /// Ceiling on ACCEPTED-but-not-yet-dispatched hydrations. A view with more
  /// distinct keys than this is offering more work than the budget can absorb;
  /// [ensure] declines the excess WITHOUT parking it, so the next frame is free
  /// to re-offer it once the backlog drains. Declining costs a map lookup and
  /// issues no I/O, so the frame-rate re-offer is bounded CPU, never traffic.
  static const int _maxQueued = 120;

  /// Most activities one request may carry. Matches the backend's own cap on
  /// the batch read, so a full batch is never rejected as oversized — a limit
  /// the client could exceed would turn a hydration into a 422 and leave the
  /// screen empty.
  static const int _maxBatchSize = 50;

  int _inFlight = 0;

  /// Completes when the batch currently carrying a storage key finishes.
  ///
  /// `BaseRepo` de-duplicates concurrent reads of one key through its own
  /// in-flight registry, but a batched read never enters it — so without this a
  /// learner opening an activity while its card is still hydrating would send a
  /// second request for the same plan, spend the allowance twice, and expose
  /// the direct read to a throttle the batch had already survived. [lookup]
  /// joins the batch instead of racing it.
  final Map<String, Future<void>> _batchInFlight = {};

  /// Keys a batch asked for and could not satisfy, with the failure behind it.
  ///
  /// Read by [lookup] so a caller joining a failed batch shares its outcome
  /// instead of re-asking — otherwise every joiner sends its own request at the
  /// moment the backend is already failing. Cleared when the key next succeeds
  /// or is re-attempted, so a failure is never sticky.
  final Map<String, Object> _unsatisfied = {};

  /// Hydrations accepted by [ensure] and awaiting a free slot. Keys here are in
  /// [_hydrating] (so a rebuild cannot enqueue them twice) and parked in
  /// [_nextAttempt] (so dropping one cannot produce a frame-rate retry).
  final Queue<_QueuedHydration> _queued = Queue();

  @visibleForTesting
  int get inFlightCount => _inFlight;

  @visibleForTesting
  int get queuedCount => _queued.length;

  /// Test seam: this repo's clock. Backoff is wall-clock, so tests would
  /// otherwise need real delays.
  ///
  /// Reads and writes [RateLimitPause.now] rather than holding its own, so the
  /// attempt cooldowns here and the shared pause can never disagree about what
  /// time it is. Two seams for one subsystem meant a test advancing this one
  /// left the pause frozen, and the pause then never lapsed — which reads in
  /// the output as the suppression logic being wrong rather than the clocks
  /// being out of step.
  @visibleForTesting
  static DateTime Function() get now => RateLimitPause.now;

  @visibleForTesting
  static set now(DateTime Function() clock) => RateLimitPause.now = clock;

  /// Drops all suppression state, persisted verdicts included. Exposed for
  /// tests and for an explicit user-initiated refresh, which must never be
  /// suppressed — which is why [_confirmedRemoved] clears here too. Besides
  /// the retention window lapsing, it is the only way back out of the removed
  /// gate, since nothing else can clear an id the repo refuses to re-request.
  @visibleForTesting
  void resetBackoff() {
    _nextAttempt.clear();
    _confirmedRemoved.clear();
    _unsatisfied.clear();
    _rateLimitPause.reset();
    // The backlog goes too. Dropping it loses nothing: clearing [_nextAttempt]
    // above un-parks every queued key, so `build()` re-offers them on the next
    // frame and they hydrate under the fresh budget. Keeping them would instead
    // replay a pre-refresh backlog against the post-refresh view. In-flight
    // requests are deliberately NOT touched — [_inFlight] is decremented by
    // their own completion, and zeroing it here would let the next [_pump]
    // exceed [_maxInFlight].
    for (final item in _queued) {
      _hydrating.remove(item.key);
    }
    _queued.clear();
  }

  /// Test seam: simulate the repo having just been rate-limited, without
  /// needing a live 429 from the network layer. [pause] stands in for the
  /// server's `Retry-After`, so it also covers the header being honoured.
  @visibleForTesting
  void rateLimitedForTesting([
    Duration pause = RateLimitPause.defaultDuration,
  ]) => _rateLimitPause.recordFailure(
    PangeaHttpException(
      statusCode: 429,
      method: 'GET',
      path: '/test',
      retryAfter: pause,
    ),
  );

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

  /// The viewer's display language (L2 when the "app in target language"
  /// toggle is on, else L1), sent as the endpoint's `l1` param so activity
  /// content follows the toggle (#8397). The `?? 'en'` covers a set-up
  /// controller whose user has no languages yet — a different case from the
  /// controller not existing, which [_request] gates.
  String get _viewerDisplayLanguage =>
      MatrixState.pangeaController.userController.displayLanguageCode ?? 'en';

  /// Null until `MatrixState` has assigned `pangeaController`, which it does in
  /// `initState` after `initMatrix()`. Every entry point below turns that null
  /// into its own "could not do it" value, so nothing in this repo touches the
  /// controller — or the network — before it exists.
  ///
  /// The gate is on the whole request, not just on [_viewerDisplayLanguage],
  /// because the repo reaches the controller down THREE paths and two of them
  /// ignore [l1]:
  ///  - [_viewerDisplayLanguage] here, which crashed outright (Sentry
  ///    CLIENT-D43): it runs while building the request, outside
  ///    `BaseRepo._fetch`'s try/catch, so the `LateInitializationError`
  ///    escaped the repo.
  ///  - `BaseRepo.createRequests()`, for the access token — inside that
  ///    try/catch, so it degrades to `Result.error`.
  ///  - `PersistentRepoCache.init()`, via `BaseRepo._cacheInit`. This one is
  ///    the reason an explicit [l1] is not exempt: `_cacheInit` is a
  ///    `late final` Future, so ONE early failure is memoized and re-thrown by
  ///    every later `get` for the life of the process, from outside any
  ///    try/catch. Letting a single early call through would wedge the repo's
  ///    cache permanently, not just lose that one plan.
  ///
  /// Declining is not reported: too early is expected during startup and
  /// non-actionable, so it is not worth a Sentry event.
  ActivityPlanFetchRequest? _request(
    String activityId,
    String? l1, {
    String? version,
  }) {
    if (!MatrixState.isPangeaControllerInitialized) return null;
    return ActivityPlanFetchRequest(
      activityId: activityId,
      l1: l1 ?? _viewerDisplayLanguage,
      version: version,
    );
  }

  /// The plan for [activityId], localized to [l1] (the viewer's display
  /// language by default), with media resolved. Cached (TTL + in-flight dedup); null on fetch failure.
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
    // Answered from memory, before any request is built: this is the same
    // answer the backend already gave for this id, so re-asking can only cost a
    // round trip and another 404. Checked ahead of [_request] so the gate does
    // not depend on the controller being up, mirroring [ensure]'s ordering.
    // The persisted-verdict load is awaited here — on the one path every fetch
    // drains into — so a verdict persisted by a PRIOR session suppresses a
    // cold start's first reads too, not just re-reads (CLIENT-EB0).
    if (await _confirmedRemoved.contains(activityId)) {
      return const ActivityPlanLookup(ActivityPlanLookupStatus.removed);
    }
    // The pause is OBSERVED here, not only armed here. [ensure] used to be the
    // only gate, which left every direct caller — the start page, the summary
    // read — walking through an armed pause to re-ask a server that had just
    // said stop. "We stop when the server says stop" has to hold on the one
    // path every fetch drains into, or it does not hold at all. A cached plan
    // is unaffected: [cachedPlan] answers without reaching this, so a pause
    // suppresses re-fetching, never reading.
    final request = _request(activityId, l1, version: version);
    // Not knowable yet, not gone: `failed` is the transient status, so callers
    // keep the activity and retry rather than treating it as removed.
    if (request == null) {
      return const ActivityPlanLookup(ActivityPlanLookupStatus.failed);
    }
    // The pause suppresses ASKING, never answering. A plan already in the TTL
    // cache costs no request, so withholding it would turn a throttle into a
    // blank surface for a learner who could have been served from memory —
    // strictly worse than before the pause existed. Only a read that would
    // actually reach the network is gated, which is why the cache is consulted
    // first and `forceRefresh` (which will fetch regardless) is not exempt.
    // Answerable from cache: serve it. Checked BEFORE the batch join below,
    // because a batch registers every key it was given while the prefetch asks
    // only for the ones it could not already answer — so joining first would
    // make a cached activity wait out an unrelated key's network read, up to
    // the full request timeout, to return something it had all along.
    if (!forceRefresh && getCached(request) != null) {
      return _servedFromCache(activityId, request, forceRefresh);
    }

    // Join a batch already carrying this key instead of racing it with a second
    // request for the same plan.
    final inFlight = _batchInFlight[request.storageKey];
    if (inFlight != null) {
      // Awaited even for a forced refresh, which must not RACE the batch: both
      // write the same cache entry, and with no ordering the batch's older
      // response could land last and overwrite the fresher content the refresh
      // was asked for. A refresh still refetches afterwards — it only stops
      // being concurrent with the read it supersedes.
      await inFlight;
    }
    if (!forceRefresh) {
      if (inFlight != null) {
        final landed = _resolved[request.storageKey];
        if (landed != null) {
          return ActivityPlanLookup(ActivityPlanLookupStatus.found, landed);
        }
        if (await _confirmedRemoved.contains(activityId)) {
          return const ActivityPlanLookup(ActivityPlanLookupStatus.removed);
        }
      }
    }

    // The batch tried this key and could not satisfy it. Falling through to a
    // fetch would send one request per caller at the exact moment the backend
    // is already failing — the fan-out this path exists to remove, re-appearing
    // under load. Checked whether or not a batch is still in flight: the record
    // is what stops the NEXT caller too, not just the ones that happened to
    // arrive mid-request. It is not sticky — `ensure` clears it when the key's
    // cooldown lapses and it is offered again.
    if (!forceRefresh) {
      final failure = _unsatisfied[request.storageKey];
      if (failure != null) {
        return ActivityPlanLookup(
          ActivityPlanLookupStatus.failed,
          null,
          failure,
        );
      }
    }
    final servableFromCache = !forceRefresh && getCached(request) != null;
    if (_rateLimitPause.isPaused && !servableFromCache) {
      _rateLimitPause.reportSuppressionOnce({'activityId': activityId});
      return ActivityPlanLookup(
        ActivityPlanLookupStatus.failed,
        null,
        RateLimitedException(),
      );
    }
    final result = await get(request, forceRefresh: forceRefresh);
    if (result.isError) {
      final error = result.asError!.error;
      // A 429 is a statement about RATE, not about this key, so it pauses the
      // whole repo. Per-key backoff alone cannot honour it: the map hydrates
      // one key per visible pin, and K keys each backing off independently
      // still emit K/cooldown requests.
      _rateLimitPause.recordFailure(error);
      final status = classifyLookupError(error);
      if (status == ActivityPlanLookupStatus.removed) {
        _confirmedRemoved.mark(activityId);
      }
      return ActivityPlanLookup(status, null, error);
    }

    _confirmedRemoved.unmark(activityId);
    final resolved = await resolveMedia(result.asValue!.value.plan);
    _resolved[request.storageKey] = resolved;
    _unsatisfied.remove(request.storageKey);
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

  /// A gone activity re-fails identically on every surface that references
  /// it; the first event per session carries the whole signal (CLIENT-EB0).
  /// Keyed by activity id — not storage key — matching [_confirmedRemoved]:
  /// the activity is gone, so every l1/version variant is the same fact.
  @override
  String? reportOnceKey(ActivityPlanFetchRequest request, Object error) =>
      PangeaHttpException.statusCodeOf(error) == 404
      ? 'activity-plan-404:${request.activityId}'
      : null;

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
    // Same answer as a cache miss, and the caller's next move is the same:
    // [ensure], which will also decline until the controller lands.
    if (request == null) return null;
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
  /// Returns whether this call ACCEPTED the work — dispatched it, or queued it
  /// behind [_maxInFlight]. It is not a promise that a request left the device:
  /// a queued entry is dropped if the backend rate-limits us before its slot
  /// comes up. Callers may ignore it; it exists so the suppression policy is
  /// observable without reaching into private state. Tests that need dispatch
  /// rather than acceptance read [inFlightCount] / [queuedCount].
  bool ensure(
    String activityId, {
    String? l1,
    String? version,
    bool revalidate = false,
  }) {
    // A confirmed-removed id can't hydrate; re-fetching on every rebuild of
    // the sync getter would loop 404s. [lookup] gates on the same cache, so
    // this is not what makes the suppression correct — it is what keeps a
    // hydration that cannot succeed from spending a `_hydrating` slot and a
    // 60s `_nextAttempt` park, and what lets the caller see `false`.
    // Synchronous, so on a cold start it cannot see not-yet-loaded persisted
    // verdicts; [lookup] awaits the load and catches those.
    if (_confirmedRemoved.containsSync(activityId)) return false;
    final request = _request(activityId, l1, version: version);
    // Declines WITHOUT parking the key: the controller lands within a frame or
    // two of startup, so the next rebuild must be free to fetch. Parking here
    // would spend a 60s cooldown on a condition that clears in milliseconds.
    if (request == null) return false;
    final key = request.storageKey;
    // Checked before `_revalidated.add` so a revalidate token is never spent
    // on a call that is about to bail.
    if (_hydrating.contains(key)) return false;
    final at = now();
    // The repo-wide pause is tested BEFORE [revalidate] is resolved, for two
    // separate reasons.
    //
    // It has to gate revalidating calls too. A 429 is a statement about RATE,
    // not about a key, so "we stop when the server says stop" cannot carry an
    // exemption — and the block below is skipped wholesale by a revalidate,
    // because re-fetching PAST a cached, already-attempted entry is the entire
    // point of revalidate. Leaving the pause inside that block therefore made
    // every revalidating call walk straight through an armed pause.
    //
    // And it has to run before `_revalidated.add`, so bailing here cannot spend
    // the once-per-session revalidate token on a call that never fetched.
    if (_rateLimitPause.isPaused) return false;
    final doRevalidate = revalidate && _revalidated.add(key);
    if (!doRevalidate) {
      if (_resolved.containsKey(key)) return false;
      final retryAt = _nextAttempt[key];
      if (retryAt != null && at.isBefore(retryAt)) return false;
    }
    // Declines WITHOUT parking: a saturated backlog is a statement about the
    // queue, not about this key, so the next frame must be free to re-offer it.
    if (_queued.length >= _maxQueued) return false;
    // PARK BEFORE THE I/O, not after it resolves. Every failure mode — 429,
    // 5xx, network, timeout, a `.plan` mapping throw, and anything added
    // later — is covered by this single line, because it does not depend on
    // classifying the outcome. This is the guard the three outcome-keyed sets
    // above could never be. Parking at ENQUEUE, not at dispatch, is what keeps
    // a queued key from being re-offered on every frame while it waits.
    _nextAttempt[key] = now().add(_attemptCooldown);
    // The previous attempt's failure must not answer for this one — without
    // this a key that failed once would keep reporting that failure to every
    // joining caller instead of being re-read.
    _unsatisfied.remove(key);
    _hydrating.add(key);
    _queued.add((
      activityId: activityId,
      l1: l1,
      version: version,
      key: key,
      forceRefresh: doRevalidate,
    ));
    _schedulePump();
    return true;
  }

  /// Whether a pump is already queued for the end of this turn.
  bool _pumpScheduled = false;

  /// Dispatches after the current synchronous pass, not during it.
  ///
  /// This is what makes a screen cost ONE request. [ensure] is called per card
  /// from `build()`, so a frame offers its keys one at a time; pumping inline
  /// meant the first key was already in flight before the second arrived, and
  /// a 12-card screen dispatched 12 times — batching that never batched. A
  /// microtask runs before the next event-loop turn, so nothing is delayed in
  /// any sense a learner could perceive; it only lets the frame finish
  /// enqueuing first.
  void _schedulePump() {
    if (_pumpScheduled) return;
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      _pump();
    });
  }

  /// Dispatches from [_queued] while a slot is free, then stops.
  ///
  /// Re-entered from each completion, so one freed slot starts exactly one
  /// successor. The loop is safe against its own dispatches: `getPlan` hands
  /// back its Future synchronously and `whenComplete` cannot run before this
  /// method yields, so [_inFlight] is already incremented for every dispatch by
  /// the time the next iteration tests it.
  void _pump() {
    while (_inFlight < _maxInFlight && _queued.isNotEmpty) {
      if (_rateLimitPause.isPaused) {
        // Rate-limited while this backlog waited. Draining it anyway would just
        // spend the NEXT window the moment the pause lifts: the same burst,
        // spread thin, not prevented. Dropping is safe because `build()`
        // re-offers every key on the next frame.
        //
        // The attempt park is released with them. These entries never reached
        // the network, so there is no attempt to back off from — and leaving
        // them parked for the full [_attemptCooldown] would outlast a shorter
        // pause: the server says come back in 5s, and the cooldown then holds
        // the screen empty for the remaining 55. That could not happen while
        // the pause was itself a hardcoded 60s, which is exactly why honouring
        // `Retry-After` is what surfaced it.
        for (final item in _queued) {
          _hydrating.remove(item.key);
          _nextAttempt.remove(item.key);
        }
        _queued.clear();
        return;
      }
      // Bounded by what is FREE, not by the request-size cap: taking a full
      // batch while 12 activities are still hydrating would put 62 in flight
      // and defeat the very bound this loop tests.
      final batch = _takeBatch(
        (_maxInFlight - _inFlight).clamp(0, _maxBatchSize),
      );
      if (batch.isEmpty) return;
      _inFlight += batch.length;
      // Registered for the NETWORK window only — the span in which a concurrent
      // [lookup] would otherwise send a second request for a key this batch is
      // already fetching. Cleared before the resolve phase so the map never
      // advertises a wait that has already finished.
      final prefetch = _prefetchBatch(batch);
      for (final item in batch) {
        _batchInFlight[item.key] = prefetch;
      }
      final hydration = prefetch.then((_) {
        for (final item in batch) {
          _batchInFlight.remove(item.key);
        }
        return _resolveBatch(batch);
      });
      hydration
          .catchError((Object e, StackTrace s) {
            // Fire-and-forget, and the response mapping runs outside the
            // network layer's try/catch, so without this a malformed body is an
            // unhandled async error. The parked entries stay put, so they
            // cannot re-arm.
            ErrorHandler.logError(
              e: e,
              s: s,
              data: {
                'activityIds': batch.map((i) => i.activityId).toList(),
                'l1': batch.first.l1,
              },
              level: SentryLevel.warning,
            );
          })
          .whenComplete(() {
            _inFlight -= batch.length;
            for (final item in batch) {
              _hydrating.remove(item.key);
              _batchInFlight.remove(item.key);
            }
            _schedulePump();
          });
    }
  }

  /// Takes the next group of queued keys that can travel in ONE request.
  ///
  /// A batch carries a single `l1` for every activity in it, so the group is
  /// cut at the first key with a different one rather than reordering the
  /// queue: hydration order is the order surfaces asked, and a learner watching
  /// a screen fill in should not see it rearranged to suit the transport. In
  /// practice one screen shares one display language and the cut never fires.
  ///
  /// A `forceRefresh` (revalidating) key is taken alone. The batch read always
  /// returns current content, so it cannot express "ignore your cache for this
  /// one and not those" — grouping them would silently downgrade a revalidate
  /// into an ordinary read.
  /// One activity appears at most ONCE per request. The wire format keys pinned
  /// versions by activity id, so the same activity at two versions — a pinned
  /// session read and an unpinned map read, say — cannot both be expressed, and
  /// the single returned plan would then be cached under BOTH version keys. A
  /// learner would be scored against roles and goals from a version they were
  /// never pinned to. The later one waits for the next request instead.
  List<_QueuedHydration> _takeBatch(int capacity) {
    if (_queued.isEmpty || capacity <= 0) return const [];
    final first = _queued.removeFirst();
    if (first.forceRefresh) return [first];
    final batch = <_QueuedHydration>[first];
    final taken = {first.activityId};
    final deferred = <_QueuedHydration>[];
    while (batch.length < capacity && _queued.isNotEmpty) {
      final next = _queued.first;
      if (next.l1 != first.l1 || next.forceRefresh) break;
      _queued.removeFirst();
      if (taken.add(next.activityId)) {
        batch.add(next);
      } else {
        deferred.add(next);
      }
    }
    // Deferred keys go back at the FRONT, in order: they were asked for before
    // everything still queued behind them, and a key that keeps losing its
    // place would starve.
    for (final item in deferred.reversed) {
      _queued.addFirst(item);
    }
    return batch;
  }

  /// Reads a whole batch in one request and files each outcome where the
  /// single-read path files it — the cache, the removed-verdict cache, or
  /// nowhere (left parked, to be retried).
  ///
  /// A single-activity batch still goes through here rather than falling back
  /// to [getPlan]: one code path means the two cannot answer differently, and
  /// the backend charges the same either way.
  /// Reads a batch by PREFILLING the cache, then letting the ordinary
  /// single-read path serve every key from it.
  ///
  /// The batch does exactly one thing: turn N round trips into one. Everything
  /// that happens to a plan afterwards — the cache read, the TTL, media
  /// resolution, de-duplication against a concurrent read, the removed-verdict
  /// gate, the rate-limit pause — stays in [lookup] and `BaseRepo.get`, which
  /// already do all of it.
  ///
  /// This shape is deliberate and was arrived at the hard way. The first
  /// version accepted responses itself, in parallel to `BaseRepo`, and had to
  /// re-derive each of those behaviours; review found six of them missing one
  /// at a time, because nothing about the new path made their absence visible.
  /// A prefetch cannot have that bug class: there is no second acceptance path
  /// to forget anything in.
  Future<void> _prefetchBatch(List<_QueuedHydration> batch) async {
    final l1 = batch.first.l1 ?? _viewerDisplayLanguage;

    // What the batch should actually ask for. A key already answerable without
    // the network is dropped here rather than fetched and thrown away.
    final wanted = <_QueuedHydration>[];
    for (final item in batch) {
      if (await _confirmedRemoved.contains(item.activityId)) continue;
      final request = _requestFor(item, l1);
      if (item.forceRefresh) {
        // A refresh goes past the CACHE, not past a read already in progress.
        // Both would write the same entry with no ordering, so the older GET
        // could land last and overwrite the very content the refresh went to
        // fetch — and it would spend the allowance twice to do it.
        final single = inFlightFor(request);
        if (single != null) await single;
        wanted.add(item);
        continue;
      }
      // Fresh on disk, or already being read by someone else: either way the
      // single read below resolves it without a request, so including it would
      // spend allowance for nothing.
      if (getCached(request) != null || inFlightFor(request) != null) continue;
      wanted.add(item);
    }

    // Keys a SUCCESSFUL response did not come back with. A failed request is
    // handled in the catch below, which reports its own exception.
    final unsatisfied = <_QueuedHydration>[];

    if (wanted.isNotEmpty && !_rateLimitPause.isPaused) {
      final request = ActivityPlanBatchRequest(
        activityIds: wanted.map((i) => i.activityId).toList(),
        l1: l1,
        versions: {
          for (final item in wanted)
            if (item.version != null) item.activityId: item.version!,
        },
      );
      try {
        final res = await createRequests()
            .post(
              url: PApiUrls.activityBatch,
              body: request.toJson(),
              // No user-context enrichment: this is a catalog read, and the
              // learner's CEFR and gender say nothing about which plans to
              // return. Sending them would also leave the request depending on
              // the backend ignoring fields it does not model.
              enrichBody: false,
            )
            .timeout(timeout);
        final result = ActivityPlanBatchResponse.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>,
        );
        for (final item in wanted) {
          final fetched = result.activities[item.activityId];
          if (fetched != null) {
            // The ONLY write this method performs, and it is a network
            // response, so it earns a new timestamp exactly as `BaseRepo.get`'s
            // would. `shouldCache` is the same policy hook the single read
            // applies to a body whose mapping throws.
            if (shouldCache(fetched)) {
              await setCached(_requestFor(item, l1), fetched);
            } else {
              // The body came back but will not map. Recorded like any other
              // key the batch could not satisfy: without this it is skipped in
              // silence, and a caller already awaiting the batch finds no
              // outcome and sends its own request for the same unmappable plan.
              unsatisfied.add(item);
            }
          } else if (result.removed.contains(item.activityId)) {
            _confirmedRemoved.mark(item.activityId);
          } else {
            // `unavailable`, and anything the backend omitted. The read is not
            // retried here — that would be one request per unsatisfied key,
            // the fan-out this path removes — but it is RECORDED and REPORTED.
            // A single read that failed produced a Sentry event through the
            // repo layer; batching must not turn a whole screen failing to
            // hydrate into silence just because the HTTP call returned 200.
            unsatisfied.add(item);
          }
        }
      } catch (e, s) {
        // A 429 is about RATE, so it pauses every read on this budget rather
        // than the keys that happened to be in this batch.
        _rateLimitPause.recordFailure(e);
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {'activityIds': request.activityIds, 'l1': l1},
          // The shared severity table: a throttle or a gone/routine status is a
          // warning, anything else an error.
          level: PangeaHttpException.severityOf(e),
        );
        // Recorded for joining callers, but NOT added to `unsatisfied`: the
        // report above already carries this failure with its real exception,
        // and re-reporting it as the generic batch type would both duplicate it
        // and bypass ErrorHandler's per-session de-duplication for offline and
        // expired-token conditions — the two that repeat most.
        for (final item in wanted) {
          _unsatisfied[_requestFor(item, l1).storageKey] = e;
        }
      }
    }

    if (unsatisfied.isNotEmpty) {
      for (final item in unsatisfied) {
        _unsatisfied.putIfAbsent(
          _requestFor(item, l1).storageKey,
          () => const ActivityBatchUnsatisfied(),
        );
      }
      // One event for the batch, not one per activity: they failed together,
      // for one reason, and a per-key event would spend the report budget as
      // fast as the reads that failed.
      ErrorHandler.logError(
        e: const ActivityBatchUnsatisfied(),
        s: StackTrace.current,
        data: {
          'activityIds': unsatisfied.map((i) => i.activityId).toList(),
          'l1': l1,
        },
        level: SentryLevel.warning,
      );
    }
  }

  /// Resolves every key of a prefetched batch through the ordinary read.
  ///
  /// Where the prefetch landed a plan this is a cache hit and costs nothing;
  /// where it did not, the read's own gates decide what happens — and a pause
  /// armed by the prefetch stops it there, so a failed batch cannot fan back
  /// out into N single requests. Concurrent, because each one may resolve media.
  ///
  /// The batch's keys are dropped from [_batchInFlight] before this runs, so
  /// the map holds only reads that are genuinely still in the network phase.
  /// That is hygiene, not a correctness requirement: [lookup] awaits whatever
  /// it finds there, and by this point that future has already completed.
  Future<void> _resolveBatch(List<_QueuedHydration> batch) async {
    final l1 = batch.first.l1 ?? _viewerDisplayLanguage;
    await Future.wait([
      for (final item in batch)
        if (_answerableWithoutAsking(_requestFor(item, l1)))
          getPlan(item.activityId, l1: l1, version: item.version),
    ]);
  }

  /// Whether reading this key will come back without a request of its own —
  /// because the prefetch landed it, it was already cached, or someone else is
  /// already fetching it (which [BaseRepo] joins rather than duplicates).
  ///
  /// The batch resolves ONLY these. A key the batch did not satisfy — reported
  /// unavailable, or omitted — is left parked instead: reading it here would
  /// issue a single request per unsatisfied key, which is the fan-out this
  /// whole path exists to remove, arriving by the back door on exactly the
  /// degraded responses where it hurts most.
  bool _answerableWithoutAsking(ActivityPlanFetchRequest request) =>
      getCached(request) != null || inFlightFor(request) != null;

  /// The cached plan for [request], media-resolved, as a `found` lookup.
  Future<ActivityPlanLookup> _servedFromCache(
    String activityId,
    ActivityPlanFetchRequest request,
    bool forceRefresh,
  ) async {
    final result = await get(request, forceRefresh: forceRefresh);
    if (result.isError) {
      return ActivityPlanLookup(
        ActivityPlanLookupStatus.failed,
        null,
        result.asError!.error,
      );
    }
    final resolved = await resolveMedia(result.asValue!.value.plan);
    _resolved[request.storageKey] = resolved;
    _unsatisfied.remove(request.storageKey);
    // Released here as well as on the network path. A plan with less than the
    // cooldown left on its TTL hydrates fine from cache, but leaving the park
    // in place means that when the entry does expire, `ensure` refuses to
    // reload it for the rest of the minute and the card simply empties.
    _nextAttempt.remove(request.storageKey);
    notifyListeners();
    return ActivityPlanLookup(ActivityPlanLookupStatus.found, resolved);
  }

  ActivityPlanFetchRequest _requestFor(_QueuedHydration item, String l1) =>
      ActivityPlanFetchRequest(
        activityId: item.activityId,
        l1: l1,
        version: item.version,
      );

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
