import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_audio_coverage.dart';
import 'package:fluffychat/features/dosage/dosage_audio_event.dart';
import 'package:fluffychat/features/dosage/dosage_signal_identity.dart';
import 'package:fluffychat/features/dosage/dosage_signals_repo.dart';

/// One undelivered POST: the playback events observed in a period, together
/// with that period's coverage declarations.
///
/// **They travel together and are dropped together.** That is the whole design.
/// Coverage is what licenses the server to serve a zero, so a batch whose events
/// were lost while its declaration survived would have the server serve an
/// undercount as a confident total — the fabricated-zero defect wearing a
/// different hat. Keeping them in one object makes "lose the events, lose the
/// declaration, withhold the counter" true by construction rather than by
/// remembering.
class DosageAudioBatch {
  DosageAudioBatch({required this.events, required this.coverage});

  final List<DosageAudioEvent> events;
  final List<DosageAudioCoverage> coverage;

  /// Delivery attempts made so far.
  int attempts = 0;

  /// Flush ticks still to wait before the next attempt (exponential backoff).
  int backoffTicks = 0;

  bool get isEmpty => events.isEmpty && coverage.isEmpty;
}

/// Buffers audio-playback signals and their coverage declarations, and retries
/// delivery until the server takes them.
///
/// **Why listening is buffered when speaking is not.** A speaking envelope that
/// is lost is recoverable: the `m.audio` event is in Matrix and the server can
/// re-derive the magnitude from it. A listening event has no Matrix artefact —
/// nothing anywhere records that a playback happened — so a lost POST is an
/// observation gone forever. That asymmetry is the entire justification for this
/// class, and it is why the speaking call site stays fire-and-forget.
///
/// **What retry does and does not buy.** The ingest returns 202 for any
/// well-formed batch even when the database write fails, so retry converts
/// *loss before ingest* — the route absent behind its flag, an unreachable
/// network — into *delivery on enablement*. It converts nothing else. A write
/// swallowed behind a 202 is invisible to the client and always will be; the
/// only thing that makes that survivable is the server writing a batch's events
/// and its coverage in ONE transaction.
///
/// **Bounded, and the bound is a design decision, not a limit reached by
/// accident.** Memory is capped at [maxPendingBatches] × [maxEventsPerBatch],
/// and each batch gets [maxAttempts] tries on an exponential backoff before it
/// is dropped. Both limits drop a WHOLE batch, so the coverage that licensed
/// those events goes with them and the server withholds that period instead of
/// serving a short total.
///
/// PER-ACCOUNT, like [DosageEngagementTracker]: the app runs multiple Matrix
/// accounts and a shared buffer would let one account's teardown flush another's
/// observations under the wrong bearer.
///
/// Design: docs/research/104-speaking-listening-minutes-v2.md, §2b and §6.
class DosageAudioBuffer {
  /// Server batch cap for the ingest route. The accumulator seals a batch when
  /// it reaches this, so a body is never built that the route would 413.
  static const int maxEventsPerBatch = 200;

  /// Undelivered batches held at once. Twelve covers an hour of heartbeat
  /// flushes with the route absent, which is the realistic "server not deployed
  /// yet" window within one session; past it the oldest is dropped whole.
  static const int maxPendingBatches = 12;

  /// Delivery attempts per batch before it is dropped. With the backoff below
  /// this spans roughly 1 + 2 + 4 + 8 = 15 heartbeat ticks (~75 minutes) of
  /// retrying, after which a still-unreachable surface is treated as absent.
  static const int maxAttempts = 5;

  /// Batches sent per ordinary flush, so a backlog drains steadily instead of
  /// firing a dozen POSTs in one tick. Teardown lifts this — see [flush].
  static const int maxSendsPerFlush = 3;

  DosageAudioBuffer({DateTime Function()? now, http.Client? httpClient})
    : _now = now ?? DateTime.now,
      _httpClient = httpClient;

  final DateTime Function() _now;
  final http.Client? _httpClient;

  /// Per-account buffers. Each account gets its own so one account's teardown
  /// never flushes or attributes another's observations.
  static final Map<String, DosageAudioBuffer> _byAccount = {};

  /// Accounts whose flush/teardown is in flight, mapped to that close future, so
  /// a concurrent close coalesces instead of racing. Mirrors
  /// [DosageEngagementTracker]'s tombstone for the same reason: an observation
  /// recorded during logout must not open a period that would only flush after
  /// the bearer is invalidated.
  static final Map<String, Future<void>> _closing = {};

  /// The buffer for [userId], created on first use. Returns none for an unknown
  /// account (empty userId) or one whose teardown is in flight.
  static DosageAudioBuffer? forAccount(String userId) {
    if (userId.isEmpty || _closing.containsKey(userId)) return null;
    return _byAccount.putIfAbsent(userId, DosageAudioBuffer.new);
  }

  /// NON-destructive pre-logout drain, KEEPING the buffer so a FAILED logout
  /// leaves a usable one. Coalesces with any in-flight close.
  ///
  /// [accessToken] is passed by the caller because this is the LAST moment a
  /// valid bearer exists: logout invalidates it, and a buffer that had only ever
  /// seen a flush before login would otherwise hold its observations rather than
  /// send them.
  static Future<void> flushForLogout(String userId, {String? accessToken}) {
    if (userId.isEmpty) return Future.value();
    return _closing[userId] ??= () async {
      try {
        await _byAccount[userId]?.flush(
          drainAll: true,
          accessToken: accessToken,
        );
      } finally {
        _closing.remove(userId);
      }
    }();
  }

  /// Drains + drops [userId]'s buffer on that account's teardown. Awaited so the
  /// last observations are sent under the still-valid bearer.
  static Future<void> disposeAccount(
    String userId, {
    String? accessToken,
  }) async {
    if (userId.isEmpty) return;
    final inFlight = _closing[userId];
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
    }
    await (_closing[userId] ??= () async {
      try {
        await _byAccount
            .remove(userId)
            ?.flush(drainAll: true, accessToken: accessToken);
      } finally {
        _closing.remove(userId);
      }
    }());
  }

  /// Seeds a buffer for [userId] (tests only).
  @visibleForTesting
  static void debugPutAccount(String userId, DosageAudioBuffer buffer) =>
      _byAccount[userId] = buffer;

  /// Clears the per-account registry (tests only) so the app-global map does not
  /// leak between tests.
  @visibleForTesting
  static void debugResetAccounts() {
    _byAccount.clear();
    _closing.clear();
  }

  final List<DosageAudioEvent> _events = [];
  final List<DosageAudioBatch> _batches = [];
  DateTime? _periodStart;
  String? _accessToken;
  Future<void>? _flushing;

  /// Voice-send envelopes posted but not yet acknowledged.
  int _voiceSendsInFlight = 0;

  /// Whether a voice-send envelope in THIS period is known to have been lost.
  bool _voiceSendLost = false;

  /// Batches dropped by a bound, for diagnostics and for tests to assert the
  /// bound actually bites.
  int droppedBatches = 0;

  @visibleForTesting
  List<DosageAudioBatch> get pendingBatches => List.unmodifiable(_batches);

  @visibleForTesting
  List<DosageAudioEvent> get bufferedEvents => List.unmodifiable(_events);

  @visibleForTesting
  DateTime? get periodStart => _periodStart;

  @visibleForTesting
  bool get voiceSendCoveredForTest => _voiceSendCovered;

  /// Opens the coverage period. Called when the account's analytics service
  /// starts, so the declared period begins when the instrument began running
  /// rather than at the first playback — a build that observed nothing still has
  /// to say it was watching, or its zero is indistinguishable from an unknown.
  /// Idempotent: a restart does not reopen a period already running, which would
  /// silently discard the interval since it opened.
  void start() {
    if (!DosageSignalsRepo.isEnabled) return;
    _periodStart ??= _now().toUtc();
  }

  /// Records one finished playback. Synchronous, allocation-only and never
  /// throws: this runs on the playback path and must be invisible to the
  /// learner. Delivery happens later, on a flush.
  ///
  /// No-op while the feature is dark, so nothing is retained that could never be
  /// sent.
  void record(DosageAudioEvent event, {required String? accessToken}) {
    if (!DosageSignalsRepo.isEnabled) return;
    if (event.roomId.isEmpty || event.elapsedMs <= 0) return;
    _periodStart ??= _now().toUtc();
    if (accessToken != null && accessToken.isNotEmpty) {
      // Keep the freshest bearer for the eventual flush; tokens refresh
      // mid-session and a stale one would post under an expired bearer.
      _accessToken = accessToken;
    }
    if (_events.length >= maxEventsPerBatch) _seal();
    _events.add(event);
  }

  /// A voice-send envelope has been posted and not yet acknowledged.
  ///
  /// **`voice_send` coverage is the one declaration this lane cannot make
  /// atomic.** The other three categories ride in the same body as the events
  /// they license, so losing the events loses the declaration. Speaking's
  /// evidence is a message envelope on a DIFFERENT route, and it is the only
  /// evidence the server ever gets that the voice message exists — nothing
  /// enumerates a room's timeline. So a declaration that landed while its
  /// envelope did not would have the server serve a confident zero for speech
  /// it never saw.
  ///
  /// The answer is to declare `voice_send` only for a period whose envelopes we
  /// can vouch for. Anything else — one in flight at seal time, one known lost —
  /// leaves the category undeclared and the counter withheld.
  void noteVoiceSendPending() {
    if (!DosageSignalsRepo.isEnabled) return;
    _periodStart ??= _now().toUtc();
    _voiceSendsInFlight++;
  }

  /// The outcome of a voice-send envelope reported by [noteVoiceSendPending].
  void noteVoiceSendSettled({required bool delivered}) {
    if (_voiceSendsInFlight > 0) _voiceSendsInFlight--;
    if (!delivered) _voiceSendLost = true;
  }

  /// Whether this period's `voice_send` coverage may be declared.
  ///
  /// Deliberately pessimistic on both counts. An envelope still in flight at
  /// seal time is UNKNOWN, not delivered; and a loss reported after its own
  /// period was sealed withholds the current one instead, which withholds a
  /// period that was probably fine. Both err toward a withheld counter, never
  /// toward a confident zero.
  bool get _voiceSendCovered => _voiceSendsInFlight == 0 && !_voiceSendLost;

  /// Seals the current period into a pending batch: its events plus a coverage
  /// declaration for EVERY category this build instruments, whether or not any
  /// audio occurred, and restarts the period from this instant.
  ///
  /// The declaration set is [DosageCoverageCategory.values] — all four, including
  /// `voiceSend`. This is the one place the build asserts what it instruments,
  /// so if an emitter is ever removed without removing its category here, the
  /// server is told a counter is covered that nothing feeds. The parity test
  /// exists to make that a failing test rather than a silent zero.
  ///
  /// The three LISTENING categories are always declared: their events ride in
  /// this same batch, so a lost batch loses the declaration with it.
  /// `voiceSend` is declared only when [_voiceSendCovered] — see there for why
  /// it alone needs the extra condition.
  void _seal() {
    final DateTime? start = _periodStart;
    // Nothing observed and no period open: seal nothing and, crucially, START
    // nothing. Opening a period as a side effect of an empty seal would make the
    // one fact this class asserts — when the instrument was running — depend on
    // when a flush happened to fire. [start] and [record] and the explicit open
    // in [flush] are the three places that genuinely know, and they are the only
    // places allowed to say so.
    if (start == null && _events.isEmpty) return;

    final DateTime end = _now().toUtc();
    _periodStart = end;
    final bool voiceSendCovered = _voiceSendCovered;
    _voiceSendLost = false;

    final List<DosageAudioCoverage> coverage = start == null
        ? const []
        : DosageCoverageCategory.values
              .where(
                (category) =>
                    category != DosageCoverageCategory.voiceSend ||
                    voiceSendCovered,
              )
              .map(
                (category) => DosageAudioCoverage(
                  coverageId: DosageSignalIdentity.uuidV4(),
                  category: category,
                  periodStart: start,
                  periodEnd: end,
                ),
              )
              .where((declaration) => declaration.isValid)
              .toList();

    if (_events.isEmpty && coverage.isEmpty) return;

    final batch = DosageAudioBatch(
      events: List.of(_events),
      coverage: coverage,
    );
    _events.clear();

    // Capacity: drop the OLDEST batch whole. Its events and the declaration that
    // licensed them go together, so the server sees an undeclared period and
    // withholds rather than serving the remaining events as a total.
    while (_batches.length >= maxPendingBatches) {
      _batches.removeAt(0);
      droppedBatches++;
    }
    _batches.add(batch);
  }

  /// The longest a caller may WAIT on a flush. Teardown and logout await this
  /// future, and a learner logging out must not sit behind an unreachable
  /// telemetry endpoint — which, until the ingest route ships, is the normal
  /// case rather than an edge one. Twelve batches × a 10 s request timeout is
  /// two minutes of teardown if left unbounded, so it is bounded here rather
  /// than at each call site, where one forgetful caller would reintroduce it.
  static const Duration flushDeadline = Duration(seconds: 5);

  /// Seals the current period and attempts delivery of pending batches.
  ///
  /// Ordinary flushes (heartbeat, backgrounding) send at most
  /// [maxSendsPerFlush] batches and honour each batch's backoff. Teardown passes
  /// [drainAll] to make one final attempt at everything under the still-valid
  /// bearer.
  ///
  /// Never throws, and never runs two drains at once.
  ///
  /// **An ordinary flush COALESCES onto a drain in flight; a [drainAll] one
  /// CHAINS behind it.** The difference matters at teardown: coalescing a
  /// drain-all onto a heartbeat drain would have teardown wait on a pass that
  /// sends only [maxSendsPerFlush] and honours backoff, and then drop the buffer
  /// with batches still in it. So a drain-all always gets its own pass —
  /// queued behind the current one rather than racing it.
  ///
  /// Each caller awaits its own [flushDeadline]-bounded VIEW. The timeout is
  /// deliberately applied to the view and never to the latch: a timed-out latch
  /// would clear while the real drain was still posting and let a second drain
  /// start on the same batches, double-counting their attempts. Same shape, and
  /// the same reason, as the env-load latch in
  /// [DosageMessageSignals.ensureDosageEnvLoaded].
  ///
  /// A caller that times out has not lost anything by timing out: the drain
  /// keeps running and the batches stay buffered either way.
  Future<void> flush({bool drainAll = false, String? accessToken}) {
    if (accessToken != null && accessToken.isNotEmpty) {
      _accessToken = accessToken;
    }
    if (!DosageSignalsRepo.isEnabled) return Future.value();
    // A flush only happens on the analytics heartbeat, on backgrounding, or at
    // teardown — all of which mean this buffer is live and reachable by every
    // emit site, so the instrument IS running from here whether or not [start]
    // was reached. Opening the period explicitly here also self-heals the case
    // where [start] ran while the flags were still dark, which would otherwise
    // leave the counters withheld for the whole session.
    start();

    final inFlight = _flushing;
    if (inFlight != null && !drainAll) {
      return inFlight.timeout(flushDeadline, onTimeout: () {});
    }

    late final Future<void> pass;
    pass = inFlight == null
        ? _guardedDrain(drainAll)
        : inFlight.then((_) => _guardedDrain(drainAll));
    _flushing = pass;
    // Clear the latch only if it is still OURS: a drain-all chained behind this
    // pass has already replaced it, and clearing that would let a third drain
    // start alongside it.
    unawaited(
      pass.whenComplete(() {
        if (identical(_flushing, pass)) _flushing = null;
      }),
    );
    return pass.timeout(flushDeadline, onTimeout: () {});
  }

  /// One drain pass that can never throw into the latch.
  Future<void> _guardedDrain(bool drainAll) async {
    try {
      await _drain(drainAll: drainAll);
    } catch (_) {
      // Best-effort: a flush can never surface to the learner.
    }
  }

  Future<void> _drain({required bool drainAll}) async {
    _seal();
    if (_batches.isEmpty) return;

    // No bearer yet (a flush before login resolves, or after it is invalidated):
    // hold the batches rather than burn an attempt on a POST that could not have
    // been sent. The capacity bound still applies, so this cannot grow.
    final String? token = _accessToken;
    if (token == null || token.isEmpty) return;

    for (final batch in _batches) {
      if (batch.backoffTicks > 0) batch.backoffTicks--;
    }

    int sent = 0;
    final List<DosageAudioBatch> delivered = [];
    final List<DosageAudioBatch> exhausted = [];

    // Iterate a SNAPSHOT: `record` can seal a fresh batch during one of the
    // awaits below, and mutating the list under the loop would throw into a path
    // that must never throw.
    for (final batch in List.of(_batches)) {
      if (!drainAll && sent >= maxSendsPerFlush) break;
      if (!drainAll && batch.backoffTicks > 0) continue;

      batch.attempts++;
      sent++;
      final bool ok = await DosageSignalsRepo.postAudioSignals(
        events: batch.events,
        coverage: batch.coverage,
        accessToken: _accessToken ?? token,
        client: _httpClient,
      );
      if (ok) {
        delivered.add(batch);
        continue;
      }
      if (batch.attempts >= maxAttempts) {
        exhausted.add(batch);
        continue;
      }
      // 1, 2, 4, 8 ticks. Applied AFTER this flush's decrement, so a batch that
      // just failed is not retried on the very next tick.
      batch.backoffTicks = 1 << (batch.attempts - 1);
    }

    for (final batch in delivered) {
      _batches.remove(batch);
    }
    for (final batch in exhausted) {
      _batches.remove(batch);
      droppedBatches++;
    }
  }
}
