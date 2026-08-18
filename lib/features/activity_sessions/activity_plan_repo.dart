import 'dart:async';
import 'dart:collection';

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

  /// Activity ids the backend confirmed removed (404) this app session, so the
  /// repo stops re-fetching a known-missing id.
  ///
  /// Enforced in [lookup], the shared read path — NOT only in [ensure], which
  /// is where this gate first lived. [getPlan] delegates to [lookup] and
  /// [ensure] calls [getPlan], so gating there is what makes the suppression
  /// total over entry points; gating only in [ensure] left the start page and
  /// the summary read re-requesting a gone activity for as long as the surface
  /// stayed open (Sentry CLIENT-DWH: 753 events / 9 users in 24h, all for a
  /// single activity id). Keyed by activity id, not by storage key: the
  /// activity is gone, so no l1 or pinned version of it can resolve either.
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

  /// Ceiling on hydrations in flight at once.
  ///
  /// Staging 2026-08-14: 18 reads left in 30ms and 11 more in 4ms, spending the
  /// whole per-user `/choreo/*` minute budget in one frame and starving the next
  /// unrelated call — `/choreo/tokenize`, which backs free message rendering.
  ///
  /// No backoff can prevent that, and [_rateLimitedUntil] is not a counter-
  /// example: every guard in [ensure] is temporal or outcome-keyed, so on a COLD
  /// view all of them are empty BY DEFINITION. Nothing has resolved, nothing has
  /// been attempted, and no pause can be armed because no response has come back
  /// yet. [ensure] is reached from `build()`, so K cards in one frame means K
  /// synchronous passes that each clear every guard. Backoff reacts to a
  /// response; the first wave happens before any response exists. Only a bound
  /// on CONCURRENCY closes that, which is why this is a separate mechanism
  /// rather than another cooldown.
  ///
  /// 6 is chosen to be small against the 60/min budget (a cold view of 60 pins
  /// drains over seconds instead of one frame) while still hydrating a visible
  /// screen fast enough that cards do not pop in one at a time.
  static const int _maxInFlight = 6;

  /// Ceiling on ACCEPTED-but-not-yet-dispatched hydrations. A view with more
  /// distinct keys than this is offering more work than the budget can absorb;
  /// [ensure] declines the excess WITHOUT parking it, so the next frame is free
  /// to re-offer it once the backlog drains. Declining costs a map lookup and
  /// issues no I/O, so the frame-rate re-offer is bounded CPU, never traffic.
  static const int _maxQueued = 120;

  int _inFlight = 0;

  /// Hydrations accepted by [ensure] and awaiting a free slot. Keys here are in
  /// [_hydrating] (so a rebuild cannot enqueue them twice) and parked in
  /// [_nextAttempt] (so dropping one cannot produce a frame-rate retry).
  final Queue<
    ({
      String activityId,
      String? l1,
      String? version,
      String key,
      bool forceRefresh,
    })
  >
  _queued = Queue();

  @visibleForTesting
  int get inFlightCount => _inFlight;

  @visibleForTesting
  int get queuedCount => _queued.length;

  /// Test seam: [ensure]'s clock. Backoff is wall-clock, so tests would
  /// otherwise need real delays.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// Drops all suppression state. Exposed for tests and for an explicit
  /// user-initiated refresh, which must never be suppressed — which is why
  /// [_confirmedRemoved] clears here too. It is the only way back out of the
  /// removed gate, since nothing else can clear an id the repo refuses to
  /// re-request.
  @visibleForTesting
  void resetBackoff() {
    _nextAttempt.clear();
    _confirmedRemoved.clear();
    _rateLimitedUntil = null;
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

  /// The language the plan is localized to by default: the display language
  /// the app is presented in (`UserController.appLanguageCode` — the L2 under
  /// the "App in target language" toggle, else the L1; #8397), sent as the
  /// endpoint's `l1` query. The `?? 'en'` covers a set-up controller whose user
  /// has no language yet — a different case from the controller not existing,
  /// which [_request] gates.
  String get _viewerLanguage =>
      MatrixState.pangeaController.userController.appLanguageCode ?? 'en';

  /// Null until `MatrixState` has assigned `pangeaController`, which it does in
  /// `initState` after `initMatrix()`. Every entry point below turns that null
  /// into its own "could not do it" value, so nothing in this repo touches the
  /// controller — or the network — before it exists.
  ///
  /// The gate is on the whole request, not just on [_viewerLanguage], because
  /// the repo reaches the controller down THREE paths and two of them ignore
  /// [l1]:
  ///  - [_viewerLanguage] here, which crashed outright (Sentry CLIENT-D43): it
  ///    runs while building the request, outside `BaseRepo._fetch`'s try/catch,
  ///    so the `LateInitializationError` escaped the repo.
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
      l1: l1 ?? _viewerLanguage,
      version: version,
    );
  }

  /// The plan for [activityId], localized to [l1] (the display language by
  /// default — see [_viewerLanguage]), with media resolved. Cached (TTL +
  /// in-flight dedup); null on fetch failure.
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
    if (_confirmedRemoved.contains(activityId)) {
      return const ActivityPlanLookup(ActivityPlanLookupStatus.removed);
    }
    final request = _request(activityId, l1, version: version);
    // Not knowable yet, not gone: `failed` is the transient status, so callers
    // keep the activity and retry rather than treating it as removed.
    if (request == null) {
      return const ActivityPlanLookup(ActivityPlanLookupStatus.failed);
    }
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
    // the sync getter would loop 404s. [lookup] gates on the same set, so this
    // is not what makes the suppression correct — it is what keeps a hydration
    // that cannot succeed from spending a `_hydrating` slot and a 60s
    // `_nextAttempt` park, and what lets the caller see `false`.
    if (_confirmedRemoved.contains(activityId)) return false;
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
    final pausedUntil = _rateLimitedUntil;
    if (pausedUntil != null) {
      if (at.isBefore(pausedUntil)) return false;
      _rateLimitedUntil = null;
    }
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
    _hydrating.add(key);
    _queued.add((
      activityId: activityId,
      l1: l1,
      version: version,
      key: key,
      forceRefresh: doRevalidate,
    ));
    _pump();
    return true;
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
      final pausedUntil = _rateLimitedUntil;
      if (pausedUntil != null && now().isBefore(pausedUntil)) {
        // Rate-limited while this backlog waited. Draining it anyway would just
        // spend the NEXT window the moment the pause lifts: the same burst,
        // spread thin, not prevented. Dropping is safe because every queued key
        // is parked in [_nextAttempt], so `build()` re-offers it once both the
        // pause and the cooldown have lapsed.
        for (final item in _queued) {
          _hydrating.remove(item.key);
        }
        _queued.clear();
        return;
      }
      final item = _queued.removeFirst();
      _inFlight++;
      getPlan(
            item.activityId,
            l1: item.l1,
            version: item.version,
            forceRefresh: item.forceRefresh,
          )
          .catchError((Object e, StackTrace s) {
            // `getPlan` is fire-and-forget here, and `.plan`'s mapping runs
            // outside BaseRepo's try/catch, so without this a malformed body is
            // an unhandled async error. The parked entry stays put, so it
            // cannot re-arm.
            ErrorHandler.logError(
              e: e,
              s: s,
              data: {
                'activityId': item.activityId,
                'l1': item.l1,
                'version': item.version,
              },
              level: SentryLevel.warning,
            );
            return null;
          })
          .whenComplete(() {
            _inFlight--;
            _hydrating.remove(item.key);
            _pump();
          });
    }
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
