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

/// One coverage row the ingest has WRITTEN for a category — the period the
/// server currently holds open, as far as this client can tell.
///
/// It is the anchor a later seal extends from, and it moves only when a response
/// reports rows actually written. That is the whole reason it exists: a
/// declaration may only reach back to an instant the server already holds, so the
/// interval a batch ADDS is exactly the interval that batch observed. Lose the
/// batch, lose nothing but its own interval — which is the property the events
/// and their declaration riding in one body was always for.
@immutable
class _BankedPeriod {
  const _BankedPeriod({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
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
/// **Coverage EXTENDS an open period; it does not mint a new one every seal.**
/// A coverage row's identity on the server is the natural key
/// `(sender, category, period_start)` under an extend-only upsert, so
/// re-declaring the same `period_start` with a later `period_end` lengthens ONE
/// row. Minting a fresh start each seal instead banks a new row every time —
/// seven categories × twelve heartbeats an hour = eighty-four rows an hour,
/// which walks into the server's per-day anti-abuse cap in a couple of hours of
/// app-open time, at which point coverage is dropped and the learner's listening
/// counters withhold for the rest of the UTC day. Extending is what the server's
/// key was built for, and what keeps a whole school day inside the cap — and it
/// is why growing the vocabulary costs a batch's event budget rather than a
/// learner's whole afternoon of coverage.
///
/// Two rules keep extending honest, and both are about never claiming an
/// interval nobody watched:
///
///  * **A declaration may only reach back to an instant the ingest has already
///    WRITTEN** ([_banked]) — written, not merely accepted, since the route
///    answers 202 even for a failed write and reports the rows it really wrote.
///    So the interval a batch ADDS is exactly the interval it observed, and a
///    batch dropped by a bound, a bad route or a failed write takes its own
///    interval with it — the property that made events and coverage ride in one
///    body, preserved rather than traded away.
///  * **A period never crosses a UTC midnight.** The server buckets its cap on
///    `period_start`'s day, so one row spanning a week would be counted against a
///    day it barely touches; and an open period that never rolls has no bound at
///    all. Rolling at midnight splits the observed interval into segments that
///    ABUT exactly, and the server unions adjacent periods, so the union still
///    covers what was observed with no gap and no overlap.
///
/// A period also ends where OBSERVATION did. A stretch longer than
/// [maxObservedGap] means no flush fired across it, so the process was suspended
/// and nothing was watching: it is declared not in part but not at all, and the
/// next seal opens a fresh period after it.
///
/// Process restart needs no rule of its own: this buffer is in-memory, so a new
/// process starts with nothing banked, cannot extend a period whose start it has
/// forgotten, and declares from its own [start] — which is honest, because the
/// interval while it was not running is one nobody observed.
///
/// PER-ACCOUNT, like [DosageEngagementTracker]: the app runs multiple Matrix
/// accounts and a shared buffer would let one account's teardown flush another's
/// observations under the wrong bearer.
///
/// Design: docs/research/104-speaking-listening-minutes-v2.md, §2b and §6.
class DosageAudioBuffer {
  /// Items the ingest route accepts in ONE body. It counts playbacks and
  /// coverage declarations TOGETHER — they travel in one body and are written in
  /// one transaction — and a body over the cap is a 413, which is not a partial
  /// accept but the loss of that whole period's observations.
  static const int maxItemsPerBatch = 200;

  /// The longest interval one seal may declare as CONTINUOUS OBSERVATION.
  ///
  /// A flush fires on the analytics heartbeat every five minutes, on any move off
  /// `resumed`, and at teardown — so while this buffer is genuinely running, the
  /// stretch between two seals is minutes. A far longer one means no flush
  /// happened, which means the timer was not ticking, which means the process was
  /// suspended: a mobile app the OS froze, a laptop closed, a browser tab
  /// discarded. Nothing was observed then, and coverage says the instrument was
  /// RUNNING, so such a stretch is declared not in part but NOT AT ALL — the
  /// counter withholds for it and the next seal opens a fresh period after it.
  ///
  /// Six heartbeats: generous against timer drift, a slow drain and a brief
  /// device sleep, and far under any real suspension.
  static const Duration maxObservedGap = Duration(minutes: 30);

  /// Day segments one declared interval can be cut into. [maxObservedGap] is well
  /// under a day, so an interval crosses at most one midnight — two segments.
  static const int maxCoverageSegmentsPerSeal = 2;

  /// The most coverage declarations one seal can produce: every category, times
  /// the segments its interval can be cut into.
  ///
  /// The 7 is [DosageCoverageCategory.values].length restated as a literal
  /// rather than computed, because [maxEventsPerBatch] must be a compile-time
  /// constant. So it is hand-bumped whenever a category is added, and
  /// `dosage_audio_buffer_test.dart` pins it against
  /// [DosageCoverageCategory.values] and against [maxObservedGap] — a category
  /// added without bumping it here is a failing test rather than a batch the
  /// route silently 413s.
  static const int maxCoverageItemsPerBatch = 7 * maxCoverageSegmentsPerSeal;

  /// Playbacks accumulated before the accumulator seals. The route's cap minus
  /// the room the same body's coverage needs, so a full batch plus its
  /// declarations is still a body the route accepts — which is what the cap was
  /// always for, and what counting only the events would quietly miss.
  static const int maxEventsPerBatch =
      maxItemsPerBatch - maxCoverageItemsPerBatch;

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

  /// Start of the interval this buffer has OBSERVED and not yet sealed.
  ///
  /// Deliberately not called a period start any more: it is the observation
  /// cursor, and it advances to the seal instant every time. What goes on the
  /// wire as `period_start` is [_banked]-anchored and can reach further back —
  /// but only as far as an instant the server has already acknowledged.
  DateTime? _observedFrom;

  /// The coverage row the ingest has acknowledged per category — the anchor a
  /// seal extends. Written on a 2xx and nowhere else; see [_BankedPeriod].
  final Map<DosageCoverageCategory, _BankedPeriod> _banked = {};

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
  DateTime? get observedFrom => _observedFrom;

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
    _observedFrom ??= _now().toUtc();
  }

  /// Records one finished playback. Synchronous, allocation-only and never
  /// throws: this runs on the playback path and must be invisible to the
  /// learner. Delivery happens later, on a flush.
  ///
  /// No-op while the feature is dark, so nothing is retained that could never be
  /// sent.
  void record(DosageAudioEvent event, {required String? accessToken}) {
    if (!DosageSignalsRepo.isEnabled) return;
    // A null room is a surface that has none and says so; an EMPTY one is a
    // room that failed to arrive. Only the second is dropped.
    if (!event.hasWellFormedRoom || event.elapsedMs <= 0) return;
    _observedFrom ??= _now().toUtc();
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
    _observedFrom ??= _now().toUtc();
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

  /// Seals the observed interval into a pending batch: its events plus a
  /// coverage declaration for EVERY category this build instruments, whether or
  /// not any audio occurred, and moves the observation cursor to this instant.
  ///
  /// The DECLARED period is not the observed interval. It runs from the anchor
  /// [_declarationsFor] picks — this batch's own observed start, or, when the
  /// server has already acknowledged coverage right up to it, that acknowledged
  /// row's start, so the upsert extends one row instead of banking another.
  ///
  /// The declaration set is [DosageCoverageCategory.values] — all seven,
  /// including `voiceSend`. This is the one place the build asserts what it
  /// instruments,
  /// so if an emitter is ever removed without removing its category here, the
  /// server is told a counter is covered that nothing feeds. The parity test
  /// exists to make that a failing test rather than a silent zero.
  ///
  /// Reading the enum rather than a hand-written list is what makes a NEW
  /// category safe: adding one to the enum and its emitter declares it here with
  /// no edit, and an older build that has neither declares neither, so the server
  /// withholds that counter for it rather than serving its silence as a zero.
  ///
  /// The six LISTENING categories are always declared: their events ride in
  /// this same batch, so a lost batch loses the declaration with it — and, since
  /// no later seal may anchor past an interval the ingest never acknowledged,
  /// loses it for good rather than having a subsequent extension quietly cover
  /// the hole. `voiceSend` is declared only when [_voiceSendCovered], and the
  /// same anchor rule is what withholds the skipped stretch: the next seal cannot
  /// abut a row that was never declared, so it starts a fresh period after the
  /// gap instead of extending across it.
  void _seal() {
    final DateTime? start = _observedFrom;
    // Nothing observed and no period open: seal nothing and, crucially, START
    // nothing. Opening a period as a side effect of an empty seal would make the
    // one fact this class asserts — when the instrument was running — depend on
    // when a flush happened to fire. [start] and [record] and the explicit open
    // in [flush] are the three places that genuinely know, and they are the only
    // places allowed to say so.
    if (start == null && _events.isEmpty) return;

    final DateTime end = _now().toUtc();
    _observedFrom = end;
    final bool voiceSendCovered = _voiceSendCovered;

    // A stretch longer than [maxObservedGap] is a suspension, not an
    // observation: no flush fired across it, so the instrument was not running
    // and nothing may be declared for ANY of it. Claiming the recent part would
    // be the same fabricated zero in a shorter window. The events keep their own
    // timestamps and are still sent; without coverage the server withholds,
    // which is the honest answer for a stretch nobody watched.
    final bool observedContinuously =
        start != null && end.difference(start) <= maxObservedGap;

    final List<DosageAudioCoverage> coverage =
        start == null || !observedContinuously
        ? const []
        : DosageCoverageCategory.values
              .where(
                (category) =>
                    category != DosageCoverageCategory.voiceSend ||
                    voiceSendCovered,
              )
              .expand(
                (category) => _declarationsFor(
                  category: category,
                  observedStart: start,
                  observedEnd: end,
                ),
              )
              .where((declaration) => declaration.isValid)
              .toList();

    if (_events.isEmpty && coverage.isEmpty) return;

    // Only a period that actually DECLARED something discharges a known voice
    // envelope loss. Clearing the flag on a seal that emitted no coverage — a
    // zero-length period, say — would erase the loss without any period having
    // been withheld for it, and the next period would then declare `voice_send`
    // for a message the server never saw. The flag is the whole mechanism; it
    // must outlive a seal that said nothing.
    if (coverage.isNotEmpty) _voiceSendLost = false;

    final batch = DosageAudioBatch(
      events: List.of(_events),
      coverage: coverage,
    );
    _events.clear();

    // Capacity: drop the OLDEST batch whole. Its events and the declaration that
    // licensed them go together, so the server sees an undeclared period and
    // withholds rather than serving the remaining events as a total. The
    // surviving batches cannot undo that: each one was anchored at ITS seal to
    // what the ingest had acknowledged by then, which never includes an interval
    // this eviction is about to discard.
    while (_batches.length >= maxPendingBatches) {
      _batches.removeAt(0);
      droppedBatches++;
    }
    _batches.add(batch);
  }

  /// One category's declarations for the interval `[observedStart, observedEnd]`.
  ///
  /// The caller has already established that this interval was continuously
  /// observed (see [maxObservedGap]); two things happen here, and each one is a
  /// rule from the class doc made concrete.
  ///
  /// **Anchor.** If the ingest has acknowledged this category right up to the
  /// instant this interval begins, the declaration starts at THAT row's start and
  /// the server's extend-only upsert lengthens it. The condition is exact
  /// abutment — `banked.end` is the observed start, to the microsecond — because
  /// that is what makes `[anchor, observedEnd]` equal "coverage the server
  /// already has" ∪ "the interval this batch observed", and nothing else. An
  /// unacknowledged batch anchors nothing, so a batch a bound or a 404 dropped
  /// takes its own interval down with it and the server withholds that stretch.
  ///
  /// **Split.** The remainder is cut at each UTC midnight, so no row spans a day
  /// the server's cap would then mis-bucket, and no open period grows without
  /// bound. Segments abut exactly and the server merges adjacent periods, so the
  /// union is unchanged: no gap, no overlap.
  Iterable<DosageAudioCoverage> _declarationsFor({
    required DosageCoverageCategory category,
    required DateTime observedStart,
    required DateTime observedEnd,
  }) {
    final List<DosageAudioCoverage> declarations = [];
    if (!observedEnd.isAfter(observedStart)) return declarations;

    DateTime cursor = observedStart;
    final _BankedPeriod? open = _banked[category];
    // Same UTC day as well as exact abutment: a row that ends ON a midnight is
    // the previous day's, and extending it would produce the very period that
    // crosses a boundary this split exists to avoid.
    DateTime segmentStart =
        open != null &&
            open.end.isAtSameMomentAs(cursor) &&
            _isSameUtcDay(open.start, cursor)
        ? open.start
        : cursor;

    while (cursor.isBefore(observedEnd)) {
      final DateTime midnight = _nextUtcMidnight(cursor);
      final DateTime segmentEnd = midnight.isBefore(observedEnd)
          ? midnight
          : observedEnd;
      declarations.add(
        DosageAudioCoverage(
          coverageId: DosageSignalIdentity.uuidV4(),
          category: category,
          periodStart: segmentStart,
          periodEnd: segmentEnd,
        ),
      );
      cursor = segmentEnd;
      segmentStart = segmentEnd;
    }
    return declarations;
  }

  /// Records what the ingest just acknowledged, so the next seal can extend it.
  ///
  /// Only ever moves an anchor FORWARD. A batch delivered out of order — one
  /// held back by its own backoff while a later one went through — must not pull
  /// the anchor back to an older end, which would cost the next seal its
  /// extension for no gain.
  ///
  /// Called only when the response accounted for EVERY declaration the batch
  /// sent. Two things make that the bar rather than a mere 202.
  ///
  /// The route answers 202 for any well-formed batch even when the database write
  /// failed, so a 202 is not evidence a row exists; banking on one would let the
  /// next seal lengthen a row the server never held, covering an interval whose
  /// events went down with the failed write.
  ///
  /// And the count it reports is an AGGREGATE — rows written, not which ones. The
  /// server drops individual declarations that hit its per-day coverage cap or
  /// its staleness bound, so a partial count cannot say which of this batch's
  /// rows survived. Only a count equal to what was sent proves they all did.
  ///
  /// Every other outcome — a failed write, a partial count, an unreadable body, a
  /// retry the extend-only upsert resolved to a no-op — leaves the anchor where it
  /// was, and the next seal opens a fresh period. That costs one coverage row and
  /// claims nothing the server cannot corroborate.
  void _bankDelivered(List<DosageAudioCoverage> coverage) {
    for (final declaration in coverage) {
      final _BankedPeriod? open = _banked[declaration.category];
      if (open == null || declaration.periodEnd.isAfter(open.end)) {
        _banked[declaration.category] = _BankedPeriod(
          start: declaration.periodStart,
          end: declaration.periodEnd,
        );
      }
    }
  }

  /// Midnight UTC strictly after [instant] — the next day boundary, and for an
  /// instant that IS a midnight the following one rather than itself.
  static DateTime _nextUtcMidnight(DateTime instant) {
    final DateTime utc = instant.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day + 1);
  }

  static bool _isSameUtcDay(DateTime a, DateTime b) {
    final DateTime x = a.toUtc();
    final DateTime y = b.toUtc();
    return x.year == y.year && x.month == y.month && x.day == y.day;
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
    // AUTHORITATIVE, including when null. Every production caller reads the
    // account's bearer live at the moment it flushes, so a null means the token
    // is gone — after logout invalidated it — and the drain must hold rather
    // than post under a dead credential. Keeping the last-seen token here
    // instead would have teardown spend the batches' retry budget on requests
    // that cannot succeed.
    _accessToken = accessToken;
    if (!DosageSignalsRepo.isEnabled) return Future.value();

    final bool alreadyOpen = _observedFrom != null;
    // A flush only happens on the analytics heartbeat, on backgrounding, or at
    // teardown — all of which mean this buffer is live and reachable by every
    // emit site, so the instrument IS running from here whether or not [start]
    // was reached. Opening the period explicitly here also self-heals the case
    // where [start] ran while the flags were still dark, which would otherwise
    // leave the counters withheld for the whole session.
    start();
    // Seal SYNCHRONOUSLY, at the moment the flush was asked for, never inside
    // the drain. A drain can run seconds later — chained behind another pass, or
    // waiting on a slow POST — and sealing there would end the period at that
    // later instant. At teardown that is a period the buffer did not observe:
    // the account is tombstoned the moment disposal starts, so every emit site
    // is already recording nothing. This is the request time, which is exactly
    // the last moment the instrument was running.
    //
    // But only a period that was ALREADY open. If this call is what opened one,
    // there is nothing between its start and now to declare, and sealing it
    // would put a period on the wire whose length is however long two clock
    // reads happened to take.
    if (alreadyOpen) _seal();

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
      // The snapshot can outlive its contents: `record` can seal a fresh batch
      // during one of the awaits below, and sealing can evict the oldest to stay
      // inside the bound. A batch already counted as dropped must not then be
      // sent — the send would be harmless (the ids are idempotent) but the
      // bookkeeping would be a lie about what the bound actually did.
      if (!_batches.contains(batch)) continue;

      batch.attempts++;
      sent++;
      final DosageAudioPostResult result =
          await DosageSignalsRepo.postAudioSignals(
            events: batch.events,
            coverage: batch.coverage,
            accessToken: token,
            client: _httpClient,
          );
      if (result.delivered) {
        // The anchor moves ONLY here, and only when the server's own count of
        // rows WRITTEN accounts for EVERY declaration this batch sent — not on
        // the 202, which it answers even for a failed write, and not on a partial
        // count, which cannot say WHICH rows it covered.
        if (batch.coverage.isNotEmpty &&
            result.coverageWritten == batch.coverage.length) {
          _bankDelivered(batch.coverage);
        }
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
