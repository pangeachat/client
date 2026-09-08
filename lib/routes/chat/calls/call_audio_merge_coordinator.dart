import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/utils/expiring_storage_box.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_download.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merge.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merge_decision.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_writer.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';

/// Uploads the merged WAV bytes and returns the `mxc://` URI they landed at.
///
/// Injected so the coordinator's build/re-validate/send flow is testable
/// without a homeserver, exactly as [CallAudioDownloader] is for the read side
/// and [CallAudioMergedSender] is for the write side. The real implementation
/// wraps `client.uploadContent`.
typedef CallAudioMergeUploader =
    Future<Uri> Function(
      Uint8List bytes, {
      required String filename,
      required String contentType,
    });

/// Runs the merge mixer over one request. Defaults to `compute(mergeCallAudio,
/// …)` (an isolate on native); injected so tests drive the mix synchronously
/// and can throw a decode ([FormatException], terminal) or a runtime failure
/// (any other error, transient) to exercise both classifications.
typedef CallAudioMerger =
    Future<CallAudioMergeResult> Function(CallAudioMergeRequest request);

/// Elects one device to mix a finished 1:1 call's two `pangea.call_audio`
/// halves into one `pangea.call_audio_merged`, converging with bounded memory
/// and bounded retries and never SHOWING a partial merge.
///
/// This is the P3b orchestrator around the pure P3a decision core
/// ([decideCallAudioMerge]). It owns the concurrency, lifecycle, retry and
/// durability machinery the design's "Governing rules" pin down; every one of
/// those rules is honoured by a named mechanism below, and reverting a rule
/// flips a test red:
///
/// 1. **Durable, firstSeenAt-anchored index.** Unresolved calls live in an
///    [ExpiringStorageBox] keyed `roomId|callKey`, payload `{firstSeenAt,
///    attemptCount, quarantined, nextRetryAt}`. Every upsert PRESERVES the
///    immutable `firstSeenAt`; logical expiry is `firstSeenAt + indexTtl`,
///    checked in code (not off the box's own write timestamp, which a rewrite
///    refreshes), so a perpetually-incomplete call is dropped at
///    `firstSeenAt + indexTtl` however many times the drain re-upserts it.
/// 2. **Index-before-await.** The `(roomId, callKey)` is written to the index
///    SYNCHRONOUSLY at the first moment it is known (a trigger, and the top of
///    every pass) before any await or concurrency-cap admission, so a crash or
///    a cap rejection never loses the call.
/// 3. **Re-validate before BOTH upload and send.** Both re-fetch merged +
///    halves and proceed only if the verdict is still [Mergeable] with the
///    SAME coverage and no merged event.
/// 4. **Drain-until-clean coalescing.** One in-flight [_Attempt] per call; a
///    trigger during it sets `dirty`; the runner loops until a pass finishes
///    with `dirty` clear, then removes the slot in one synchronous step.
/// 6. **Disposal generation token.** Each pass captures the generation; after
///    every await and immediately before upload and before send it aborts if
///    disposed or superseded -- so NO NEW upload/send is initiated after
///    disposal.
/// 7. **Terminal-vs-transient, stage timeouts, permit-until-settle.** A narrow
///    typed distinction (a mix [FormatException] is terminal; every other mix
///    error, and every fetch/download/upload/send throw or stage timeout, is
///    transient) -- never a broad terminal catch. A global concurrency
///    semaphore caps in-flight passes; a permit is released only when the
///    underlying stage future SETTLES, so a hung stage keeps its permit.
class CallAudioMergeCoordinator {
  CallAudioMergeCoordinator({
    required RelationsFetcher relationsFetch,
    required CallAudioDownloader download,
    required CallAudioMergeUploader upload,
    required CallAudioMergedSender send,
    required ExpiringStorageBox index,
    required bool? Function(String roomId) isDmRoom,
    required String Function() myUserId,
    required String? Function() myDeviceId,
    CallAudioMerger? mix,
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? oneShotTimer,
    Timer Function(Duration, void Function())? periodicTimer,
    this.settleDelay = const Duration(seconds: 8),
    this.baseBackoff = const Duration(seconds: 30),
    this.attemptCap = 6,
    this.stageTimeout = const Duration(seconds: 60),
    this.drainInterval = const Duration(minutes: 5),
    this.indexTtl = const Duration(days: 7),
    this.mergeCeiling = _defaultMergeCeiling,
    this.maxConcurrent = 2,
  }) : _relationsFetch = relationsFetch,
       _download = download,
       _upload = upload,
       _send = send,
       _index = index,
       _isDmRoom = isDmRoom,
       _myUserId = myUserId,
       _myDeviceId = myDeviceId,
       _mix = mix ?? _defaultMix,
       _clock = clock ?? DateTime.now,
       _oneShotTimer = oneShotTimer ?? _realOneShot,
       _periodicTimer = periodicTimer ?? _realPeriodic,
       _sem = _Semaphore(maxConcurrent);

  /// The merged output ceiling: mirrors `CallAudioRecorder`'s own
  /// `_defaultMaxDuration` (30 minutes) -- the SAME recording ceiling piece-1
  /// caps each half at. A merged span past it is truncated by the mixer and
  /// comes back `complete == false`, which this coordinator treats as terminal
  /// (re-fetching the same immutable halves would truncate identically). Not a
  /// new number: it references the recorder's documented bound, which is
  /// private to `CallAudioRecorder` and so cannot be imported directly.
  static const Duration _defaultMergeCeiling = Duration(minutes: 30);

  final RelationsFetcher _relationsFetch;
  final CallAudioDownloader _download;
  final CallAudioMergeUploader _upload;
  final CallAudioMergedSender _send;
  final CallAudioMerger _mix;
  final ExpiringStorageBox _index;
  final bool? Function(String roomId) _isDmRoom;
  final String Function() _myUserId;
  final String? Function() _myDeviceId;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _oneShotTimer;
  final Timer Function(Duration, void Function()) _periodicTimer;

  /// How long after the newest half's `originServerTs` the first attempt
  /// waits, so a third half or a peer's own merge has a moment to arrive
  /// before this device posts (rule 3's settle).
  final Duration settleDelay;

  /// The election-stagger unit AND the retry-backoff base. The rank-`r`
  /// candidate waits `baseBackoff * r` after the settle (rank 0 goes first);
  /// a transient failure's next retry waits a bounded exponential multiple of
  /// this.
  final Duration baseBackoff;

  /// Transient failures past this count quarantine the index entry (no further
  /// attempts until TTL), so a permanently-failing send cannot mint an orphan
  /// upload every startup.
  final int attemptCap;

  /// The per-stage I/O deadline. Exceeding it is a TRANSIENT failure for
  /// classification, but the underlying future keeps its concurrency permit
  /// until it actually settles (rule 7, permit-until-settle).
  final Duration stageTimeout;

  /// How often the periodic drain re-evaluates backoff-elapsed index entries.
  final Duration drainInterval;

  /// The LOGICAL time-to-live, measured from the immutable `firstSeenAt`. This
  /// is what actually bounds the index; the box's own TTL is a secondary GC and
  /// should be `>=` this.
  final Duration indexTtl;

  /// The merged-output ceiling handed to the mixer (see [_defaultMergeCeiling]).
  final Duration mergeCeiling;

  /// The global concurrency bound -- at most this many passes hold a permit at
  /// once.
  final int maxConcurrent;

  final _Semaphore _sem;

  /// In-flight attempts only, one per `(roomId, callKey)`. Bounded by
  /// [maxConcurrent] running plus however many are parked on the semaphore
  /// (itself bounded by the distinct calls the index holds).
  final Map<String, _Attempt> _inFlight = HashMap<String, _Attempt>();

  int _disposalGeneration = 0;
  bool _disposed = false;
  Timer? _drainTimer;
  bool _started = false;

  // Index payload keys.
  static const _kFirstSeenAt = 'firstSeenAt';
  static const _kAttemptCount = 'attemptCount';
  static const _kQuarantined = 'quarantined';
  static const _kNextRetryAt = 'nextRetryAt';

  // ---------------------------------------------------------------------------
  // Public surface (the wiring wave subscribes these; tests drive them).
  // ---------------------------------------------------------------------------

  /// Arms the periodic drain and reconciles the durable index once. The wiring
  /// wave subscribes `onSync`/`onSyncStatus` to the handlers below; the initial
  /// scan here is durable (relations-API, not sync-window bound) so a call
  /// whose halves fell out of the timeline is still picked up.
  void start() {
    if (_disposed || _started) return;
    _started = true;
    _drainTimer ??= _periodicTimer(drainInterval, _onDrainTick);
    unawaited(_scanIndex(respectBackoff: false));
  }

  /// The post-call kick: this device just posted its OWN half. Writes the index
  /// entry SYNCHRONOUSLY (index-before-await) then schedules an evaluation.
  void onCallFinished(
    String roomId,
    String callKey,
    String myUserId,
    String? myDeviceId,
  ) {
    if (_disposed) return;
    _keepPending(_makeKey(roomId, callKey));
    _schedule(roomId, callKey, myUserId, myDeviceId);
  }

  /// A `pangea.call_audio` half for this call was seen in a sync. Index it (in
  /// case this device did not post it) and evaluate.
  void onSyncedCallAudio(String roomId, String callKey) {
    if (_disposed) return;
    _keepPending(_makeKey(roomId, callKey));
    _schedule(roomId, callKey, _myUserId(), _myDeviceId());
  }

  /// A `pangea.call_audio_merged` event for this call was seen in a sync: the
  /// call is done. Cancel any in-flight attempt and retire the index entry.
  void onSyncedMergedEvent(String roomId, String callKey) {
    final key = _makeKey(roomId, callKey);
    final attempt = _inFlight[key];
    if (attempt != null) {
      attempt.aborted = true;
      attempt.cancelDelay?.call();
    }
    unawaited(_index.remove(key));
  }

  /// A sync status transition back to `finished` (a reconnect). Re-run every
  /// in-flight attempt (coalesced) and re-scan the durable index.
  void onReconnected() {
    if (_disposed) return;
    for (final attempt in _inFlight.values) {
      attempt.dirty = true;
    }
    unawaited(_scanIndex(respectBackoff: false));
  }

  /// Bumps the disposal generation, cancels timers, and cancels in-flight
  /// delays. In-flight awaits observe the token and initiate no further
  /// upload/send. An upload/send already in flight at this instant may still
  /// land (rule 6's honest guarantee).
  void dispose() {
    _disposed = true;
    _disposalGeneration++;
    _drainTimer?.cancel();
    _drainTimer = null;
    for (final attempt in _inFlight.values) {
      attempt.aborted = true;
      attempt.cancelDelay?.call();
    }
  }

  // ---------------------------------------------------------------------------
  // Scheduling + the drain-until-clean runner (rule 4).
  // ---------------------------------------------------------------------------

  void _schedule(
    String roomId,
    String callKey,
    String myUserId,
    String? myDeviceId,
  ) {
    if (_disposed) return;
    final key = _makeKey(roomId, callKey);
    final existing = _inFlight[key];
    if (existing != null) {
      // Coalesce: a trigger during an in-flight attempt marks it dirty so the
      // runner re-runs exactly once after the current pass, never dropped and
      // never a second concurrent attempt.
      existing.dirty = true;
      return;
    }
    final attempt = _Attempt(generation: _disposalGeneration);
    _inFlight[key] = attempt;
    unawaited(_runLoop(key, roomId, callKey, attempt, myUserId, myDeviceId));
  }

  Future<void> _runLoop(
    String key,
    String roomId,
    String callKey,
    _Attempt attempt,
    String myUserId,
    String? myDeviceId,
  ) async {
    try {
      while (true) {
        attempt.dirty = false;
        await _onePass(key, roomId, callKey, attempt, myUserId, myDeviceId);
        // The final dirty-check and the slot removal are ONE synchronous
        // transition: no await sits between the pass returning and here, so a
        // trigger cannot interleave and be lost. `_superseded` is the single
        // source of truth for "this attempt must stop" -- it also covers
        // `attempt.aborted`, so a merged-event abort during the pass ends the
        // runner even when a concurrent trigger set `dirty`.
        if (attempt.dirty && !_superseded(attempt.generation, attempt)) {
          continue;
        }
        break;
      }
    } finally {
      if (identical(_inFlight[key], attempt)) {
        _inFlight.remove(key);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // One evaluation pass (design "One evaluation pass", exact order).
  // ---------------------------------------------------------------------------

  Future<void> _onePass(
    String key,
    String roomId,
    String callKey,
    _Attempt attempt,
    String myUserId,
    String? myDeviceId,
  ) async {
    // Step 1a: keep the durable entry BEFORE any await or cap admission.
    _keepPending(key);
    if (_isExpiredOrGone(key)) return;
    // A quarantined call gets NO further attempt from ANY trigger (rule 7's
    // "no further attempts"), so a permanently-failing send cannot mint an
    // orphan upload on every sync or startup -- not only the drain/scan skip it.
    if (_isQuarantined(key)) return;

    await _sem.acquire();
    final tracker = _StageTracker();
    try {
      final gen = attempt.generation;
      if (_superseded(gen, attempt)) return;

      // Step 1b: fetch merged + halves, decide.
      final merged = await _stage(
        fetchCallAudioMerged(
          fetch: _relationsFetch,
          roomId: roomId,
          callKey: callKey,
        ),
        tracker,
      );
      if (_superseded(gen, attempt)) return;
      final halves = await _stage(
        fetchCallAudio(
          fetch: _relationsFetch,
          roomId: roomId,
          callKey: callKey,
        ),
        tracker,
      );
      if (_superseded(gen, attempt)) return;

      final decided = decideCallAudioMerge(
        halves: halves,
        isDmRoom: _isDmRoom(roomId),
        myUserId: myUserId,
        myDeviceId: myDeviceId,
        mergedExists: merged.isNotEmpty,
      );
      switch (decided) {
        case AlreadyMerged():
        case TerminallyIneligible():
          await _retire(key, decided);
          return;
        case PendingIncomplete():
          _keepPending(key);
          return;
        case NotCandidate():
          // Leave the index for the real candidates; nothing for this device.
          return;
        case Mergeable():
          break;
      }
      final mergeable = decided;
      final coverage = mergeable.coverageEventIds;

      // The exact two halves this coverage names, kept for download + mix.
      // A null here means the fetched halves no longer carry both -- abort and
      // retry via a later trigger.
      final coverHalves = _halvesForCoverage(halves, coverage);
      if (coverHalves == null) return;

      // Step 2: settle from the newest half, then the rank stagger. Both
      // cancellable by a merged event or dispose.
      final newestTs = _newestTs(halves);
      final settleWait = _remainingSettle(newestTs);
      if (!await _cancellableDelay(settleWait, attempt)) return;
      if (_superseded(gen, attempt)) return;
      final stagger = baseBackoff * mergeable.myRank;
      if (!await _cancellableDelay(stagger, attempt)) return;
      if (_superseded(gen, attempt)) return;

      // Step 3: download both halves' bytes.
      final sources = <CallAudioMergeSource>[];
      for (final half in coverHalves) {
        final bytes = await _stage(
          _download(Uri.parse(half.content.url)),
          tracker,
        );
        if (_superseded(gen, attempt)) return;
        sources.add(
          CallAudioMergeSource(
            wav: bytes,
            fileStartSfuMs: half.content.fileStartSfuMs,
            senderId: half.senderId,
          ),
        );
      }

      // Step 4: RE-VALIDATE before upload (rule 3).
      if (!await _stillMergeable(
        roomId,
        callKey,
        coverage,
        myUserId,
        myDeviceId,
        key,
        tracker,
        gen,
        attempt,
      )) {
        return;
      }
      if (_superseded(gen, attempt)) return;

      // Step 5: mix. A decode ([FormatException]) is TERMINAL (immutable bad
      // input); every other mix error is TRANSIENT (runtime OOM/isolate) and
      // falls through to the outer catch. Not truncated/complete is terminal.
      final CallAudioMergeResult result;
      try {
        result = await _stage(
          _mix(
            CallAudioMergeRequest(
              sources: sources,
              expectedUsers: 2,
              maxDurationMs: mergeCeiling.inMilliseconds,
            ),
          ),
          tracker,
        );
      } on FormatException {
        await _retireTerminal(
          key,
          'undecodable half bytes (immutable bad input)',
        );
        return;
      }
      if (_superseded(gen, attempt)) return;
      if (!result.complete) {
        await _retireTerminal(
          key,
          'merged span truncated at the recording ceiling',
        );
        return;
      }

      // Step 6: upload. Disposal check immediately before (rule 6).
      if (_superseded(gen, attempt)) return;
      final uploaded = await _stage(
        _upload(
          result.wav,
          filename: 'call_audio_merged.wav',
          contentType: 'audio/wav',
        ),
        tracker,
      );
      if (_superseded(gen, attempt)) return;

      // Step 7: RE-VALIDATE again before send (rule 3), then the disposal check
      // immediately before send (rule 6).
      if (!await _stillMergeable(
        roomId,
        callKey,
        coverage,
        myUserId,
        myDeviceId,
        key,
        tracker,
        gen,
        attempt,
      )) {
        return;
      }
      if (_superseded(gen, attempt)) return;

      // Step 8: send. Non-null id -> retire; null -> the send did not land, a
      // transient (the writer never returns null for our valid key+coverage
      // except when send itself returned null).
      final sentId = await writeCallAudioMergedEvent(
        send: _send,
        callKey: callKey,
        url: uploaded.toString(),
        mimetype: 'audio/wav',
        size: result.wav.length,
        durationMs: result.durationMs,
        sampleRate: result.sampleRate,
        channels: result.channels,
        sourceEventIds: coverage,
        mergedStartSfuMs: mergeable.mergedStartSfuMs,
      );
      if (sentId == null) {
        _recordTransient(key);
        return;
      }
      await _index.remove(key);
    } on _StageTimeout {
      // Step 9: a hung stage. Transient; the permit stays held via the tracker.
      _recordTransient(key);
    } catch (_) {
      // Step 9: fetch/download/upload/send threw, or a runtime mix failure.
      // TRANSIENT -- deliberately NOT a terminal catch (only the narrow
      // FormatException around the mix stage is terminal).
      _recordTransient(key);
    } finally {
      // Permit-until-settle: release only when the last underlying stage future
      // settles. A hung stage's future is still pending here, so its permit is
      // held until it actually completes, bounding concurrent underlying ops.
      final underlying = tracker.last;
      if (underlying == null) {
        _sem.release();
      } else {
        underlying.whenComplete(_sem.release);
      }
    }
  }

  /// Re-fetches merged + halves and returns whether the call is STILL
  /// [Mergeable] with the exact [coverage] it was decided on. A now-terminal or
  /// now-merged call is retired here; any other change (coverage drift, a peer's
  /// third half, a pending regression) leaves the index for a later trigger.
  Future<bool> _stillMergeable(
    String roomId,
    String callKey,
    List<String> coverage,
    String myUserId,
    String? myDeviceId,
    String key,
    _StageTracker tracker,
    int gen,
    _Attempt attempt,
  ) async {
    final merged = await _stage(
      fetchCallAudioMerged(
        fetch: _relationsFetch,
        roomId: roomId,
        callKey: callKey,
      ),
      tracker,
    );
    // A disposal check after EVERY await (rule 6): abort the re-validation the
    // moment this attempt is superseded, rather than issuing the second fetch.
    // These reads carry no side effect, so the caller's own post-return check
    // already guards upload/send; this only makes the abort earlier and keeps
    // the "after every await" invariant uniform.
    if (_superseded(gen, attempt)) return false;
    final halves = await _stage(
      fetchCallAudio(fetch: _relationsFetch, roomId: roomId, callKey: callKey),
      tracker,
    );
    if (_superseded(gen, attempt)) return false;
    final decided = decideCallAudioMerge(
      halves: halves,
      isDmRoom: _isDmRoom(roomId),
      myUserId: myUserId,
      myDeviceId: myDeviceId,
      mergedExists: merged.isNotEmpty,
    );
    if (decided is AlreadyMerged || decided is TerminallyIneligible) {
      await _retire(key, decided);
      return false;
    }
    if (decided is! Mergeable) return false;
    return _sameCoverage(decided.coverageEventIds, coverage);
  }

  // ---------------------------------------------------------------------------
  // Triggers' index reconciliation (drain + startup scan).
  // ---------------------------------------------------------------------------

  void _onDrainTick() {
    if (_disposed) return;
    unawaited(_scanIndex(respectBackoff: true));
  }

  Future<void> _scanIndex({required bool respectBackoff}) async {
    if (_disposed) return;
    final keys = await _index.keys();
    if (_disposed) return;
    for (final key in keys) {
      // Re-read the clock per entry: the scan awaits between entries, so a
      // single captured `now` could go stale and schedule a just-expired one.
      // (The scheduled pass's own expiry check backstops this either way.)
      final now = _clock();
      final payload = _index.read(key);
      if (payload == null) continue; // box-expired/malformed; already dropped.
      final firstSeenAt = _dateOf(payload, _kFirstSeenAt);
      if (firstSeenAt == null || _logicallyExpired(firstSeenAt, now)) {
        await _index.remove(key);
        continue;
      }
      if (payload[_kQuarantined] == true) continue;
      if (respectBackoff) {
        final nextRetryAt = _dateOf(payload, _kNextRetryAt) ?? firstSeenAt;
        if (nextRetryAt.isAfter(now)) continue;
      }
      final parts = _splitKey(key);
      if (parts == null) continue;
      _schedule(parts.$1, parts.$2, _myUserId(), _myDeviceId());
    }
  }

  // ---------------------------------------------------------------------------
  // Durable index helpers (rule 1: firstSeenAt-anchored, read-modify-write).
  // ---------------------------------------------------------------------------

  /// Writes a fresh entry if absent; otherwise KEEPS the existing one untouched
  /// (never rewriting it, so `firstSeenAt` and the box's own timestamp are not
  /// refreshed). A logically expired or unanchored entry is dropped.
  void _keepPending(String key) {
    final existing = _index.read(key);
    final now = _clock();
    if (existing == null) {
      unawaited(_writeEntry(key, now, 0, false, now));
      return;
    }
    final firstSeenAt = _dateOf(existing, _kFirstSeenAt);
    if (firstSeenAt == null || _logicallyExpired(firstSeenAt, now)) {
      unawaited(_index.remove(key));
    }
    // Present and live: leave it exactly as it is.
  }

  /// Read-modify-write for a transient failure: increment `attemptCount`,
  /// PRESERVE `firstSeenAt`, set the backoff `nextRetryAt`, and quarantine past
  /// the cap. Only ever UPDATES an existing live entry: an absent or logically
  /// expired one is left gone (never resurrected with a fresh `firstSeenAt`),
  /// so a failure cannot renew a call's TTL lease -- creating an entry is
  /// `_keepPending`'s index-before-await job alone.
  void _recordTransient(String key) {
    final existing = _index.read(key);
    if (existing == null) return;
    final now = _clock();
    final firstSeenAt = _dateOf(existing, _kFirstSeenAt);
    if (firstSeenAt == null || _logicallyExpired(firstSeenAt, now)) {
      unawaited(_index.remove(key));
      return;
    }
    final attemptCount = (_intOf(existing, _kAttemptCount) ?? 0) + 1;
    final quarantined = attemptCount > attemptCap;
    final nextRetryAt = now.add(_backoff(attemptCount));
    unawaited(
      _writeEntry(key, firstSeenAt, attemptCount, quarantined, nextRetryAt),
    );
  }

  Future<void> _writeEntry(
    String key,
    DateTime firstSeenAt,
    int attemptCount,
    bool quarantined,
    DateTime nextRetryAt,
  ) {
    return _index.write(key, {
      _kFirstSeenAt: firstSeenAt.toIso8601String(),
      _kAttemptCount: attemptCount,
      _kQuarantined: quarantined,
      _kNextRetryAt: nextRetryAt.toIso8601String(),
    });
  }

  Future<void> _retire(String key, CallAudioMergeVerdict decided) async {
    if (decided is TerminallyIneligible) {
      Logs().i('Call audio merge retired terminal ($key): ${decided.reason}');
    }
    await _index.remove(key);
  }

  Future<void> _retireTerminal(String key, String why) async {
    Logs().i('Call audio merge retired terminal ($key): $why');
    await _index.remove(key);
  }

  /// True once an entry is past its logical TTL, so a caller can skip and drop
  /// it. Anchored to the immutable `firstSeenAt`, never the box's own write
  /// timestamp (which a rewrite refreshes).
  bool _isExpiredOrGone(String key) {
    final existing = _index.read(key);
    if (existing == null) return true;
    final firstSeenAt = _dateOf(existing, _kFirstSeenAt);
    if (firstSeenAt == null) return true;
    return _logicallyExpired(firstSeenAt, _clock());
  }

  bool _isQuarantined(String key) => _index.read(key)?[_kQuarantined] == true;

  bool _logicallyExpired(DateTime firstSeenAt, DateTime now) =>
      now.difference(firstSeenAt) > indexTtl;

  /// A bounded exponential backoff off [baseBackoff]. Bounded so a large
  /// `attemptCount` cannot overflow the shift.
  Duration _backoff(int attemptCount) {
    final shift = (attemptCount - 1).clamp(0, 16);
    return baseBackoff * (1 << shift);
  }

  // ---------------------------------------------------------------------------
  // Stage timeout + concurrency (rule 7).
  // ---------------------------------------------------------------------------

  /// Races [raw] against a [stageTimeout] timer. A timeout throws
  /// [_StageTimeout] (transient) but [raw] keeps running; [tracker.last] is set
  /// to `raw`'s settle so the caller's permit release waits for the REAL future,
  /// not the wrapper timeout.
  Future<T> _stage<T>(Future<T> raw, _StageTracker tracker) {
    tracker.last = raw.then((_) {}, onError: (_, _) {});
    final completer = Completer<T>();
    final timer = _oneShotTimer(stageTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(const _StageTimeout());
      }
    });
    raw
        .then(
          (value) {
            if (!completer.isCompleted) completer.complete(value);
          },
          onError: (Object error, StackTrace stack) {
            if (!completer.isCompleted) completer.completeError(error, stack);
          },
        )
        .whenComplete(timer.cancel);
    return completer.future;
  }

  /// Waits [d], returning true if it elapsed and false if it was cancelled (a
  /// merged event or dispose). A non-positive delay elapses immediately.
  Future<bool> _cancellableDelay(Duration d, _Attempt attempt) {
    if (_superseded(attempt.generation, attempt)) return Future.value(false);
    if (d <= Duration.zero) return Future.value(true);
    final completer = Completer<bool>();
    final timer = _oneShotTimer(d, () {
      if (!completer.isCompleted) completer.complete(true);
    });
    attempt.cancelDelay = () {
      if (!completer.isCompleted) {
        timer.cancel();
        completer.complete(false);
      }
    };
    return completer.future.whenComplete(() => attempt.cancelDelay = null);
  }

  bool _superseded(int generation, _Attempt attempt) =>
      _disposed || generation != _disposalGeneration || attempt.aborted;

  // ---------------------------------------------------------------------------
  // Small pure helpers.
  // ---------------------------------------------------------------------------

  static String _makeKey(String roomId, String callKey) => '$roomId|$callKey';

  static (String, String)? _splitKey(String key) {
    final i = key.indexOf('|');
    if (i <= 0 || i >= key.length - 1) return null;
    return (key.substring(0, i), key.substring(i + 1));
  }

  /// The two halves whose event ids are exactly [coverage], in coverage order,
  /// or null if the fetched halves no longer carry both (a caller aborts).
  static List<CallAudioRecording>? _halvesForCoverage(
    List<CallAudioRecording> halves,
    List<String> coverage,
  ) {
    final byId = <String, CallAudioRecording>{
      for (final h in halves) h.eventId: h,
    };
    final out = <CallAudioRecording>[];
    for (final id in coverage) {
      final h = byId[id];
      if (h == null) return null;
      out.add(h);
    }
    return out;
  }

  static bool _sameCoverage(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static DateTime _newestTs(List<CallAudioRecording> halves) {
    var newest = halves.first.originServerTs;
    for (final h in halves) {
      if (h.originServerTs.isAfter(newest)) newest = h.originServerTs;
    }
    return newest;
  }

  /// How much of [settleDelay] is left, measured from the newest half's
  /// `originServerTs` against the local clock. Non-positive when already
  /// elapsed (the caller then skips the wait).
  Duration _remainingSettle(DateTime newestTs) {
    final elapsed = _clock().difference(newestTs);
    final remaining = settleDelay - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static DateTime? _dateOf(Map<String, dynamic>? payload, String key) {
    if (payload == null) return null;
    final raw = payload[key];
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  static int? _intOf(Map<String, dynamic>? payload, String key) {
    if (payload == null) return null;
    final raw = payload[key];
    return raw is int ? raw : null;
  }

  static Future<CallAudioMergeResult> _defaultMix(
    CallAudioMergeRequest request,
  ) => compute(mergeCallAudio, request);

  static Timer _realOneShot(Duration d, void Function() cb) => Timer(d, cb);

  static Timer _realPeriodic(Duration d, void Function() cb) =>
      Timer.periodic(d, (_) => cb());
}

/// One in-flight attempt's mutable coordination state.
class _Attempt {
  _Attempt({required this.generation});

  /// The disposal generation captured when this attempt began. A pass aborts
  /// once the coordinator's generation moves past it.
  final int generation;

  /// Set by a trigger arriving during this attempt (drain-until-clean, rule 4).
  bool dirty = false;

  /// Set by a merged-event trigger or dispose to short-circuit this attempt.
  bool aborted = false;

  /// Cancels this attempt's currently pending settle/backoff delay, if any.
  void Function()? cancelDelay;
}

/// Carries the last-started stage's underlying future so a pass releases its
/// concurrency permit only when that future SETTLES, not when a wrapper timeout
/// fires (rule 7, permit-until-settle). Stages run sequentially, so at most one
/// underlying future is still pending when a pass ends (a hung stage).
class _StageTracker {
  Future<void>? last;
}

/// Thrown by [CallAudioMergeCoordinator._stage] when a stage exceeds its
/// timeout. A TRANSIENT signal, distinct from a decode [FormatException].
class _StageTimeout implements Exception {
  const _StageTimeout();

  @override
  String toString() => 'CallAudioMerge stage timed out';
}

/// A counting semaphore: at most `max` permits outstanding. Over-cap acquirers
/// WAIT (they are not dropped -- the durable index keeps their calls alive
/// meanwhile).
class _Semaphore {
  _Semaphore(this._max);

  final int _max;
  int _outstanding = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_outstanding < _max) {
      _outstanding++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      // Hand the permit straight to the next waiter (no decrement).
      _waiters.removeFirst().complete();
    } else if (_outstanding > 0) {
      _outstanding--;
    }
  }
}
