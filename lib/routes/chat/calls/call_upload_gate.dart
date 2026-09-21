import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';

/// Whether [error] is the choreographer saying it is under pressure, as opposed
/// to saying something about the request or about this device's own network.
///
/// Only three shapes count. A `TimeoutException` raised by the request itself is
/// the dominant symptom of an overloaded backend: it stopped answering. A 429 is
/// the server asking us to stop in so many words. A 5xx is it failing under us.
///
/// A 4xx is deliberately NOT counted: it is a statement about the request, and
/// backing off every upload because one chunk was malformed would cost a whole
/// call's speech for a bug on our side. Nor are `SocketException` and
/// `ClientException`, which are indistinguishable from the learner's own wifi
/// dropping — this exists to protect the server, not to react to one device's
/// connection.
///
/// Mirrors how [RateLimitPause] reads a 429, through
/// [PangeaHttpException.statusCodeOf] rather than a type test, so a not-yet-
/// migrated raw `Response` throw site is read the same way.
bool choreoUnderPressure(Object error) {
  if (error is TimeoutException) return true;
  final status = PangeaHttpException.statusCodeOf(error);
  if (status == null) return false;
  return status == 429 || status >= 500;
}

/// Bounds how many uploads this DEVICE is waiting on at once, and stops it
/// hammering a choreographer that is already failing.
///
/// "Waiting on" and not "has open" — the distinction is real and the permit
/// note in [run] explains it. An abandoned upload keeps its socket, because
/// nothing this app sends is abortable, so this counts what the device is still
/// expecting an answer to.
///
/// A call ships up to 2.88 MB of WAV per chunk (`PcmChunker.maxBytes`) and hands
/// each one over without waiting. Nothing counted how many were outstanding, and
/// nothing remembered that the last twenty had failed — so a choreographer
/// returning 500 instantly saw three full uploads per chunk within about three
/// seconds, from every device on every call, for as long as it stayed down.
///
/// Two mechanisms, one object:
///
/// **A concurrency cap.** [maxInFlight] permits, handed out first-come. A caller
/// that cannot get one inside its own attempt budget is refused with a
/// [TimeoutException] — which is exactly the failure its retry loop already
/// knows how to handle.
///
/// **A circuit breaker.** [failuresToOpen] consecutive server-classified
/// failures open it for [openFor]; then exactly one caller is admitted as a
/// probe, and whether IT succeeds decides — an upload that was already in
/// flight when the breaker opened decides nothing either way, because it says
/// nothing about the state that opened it: not by succeeding, and not by
/// failing with something the classifier does not count. The probe is a real
/// chunk upload: there is no synthetic prober and no background timer, so a
/// device with nothing to send makes no requests at all.
///
/// **What happens to audio while it is open is a decision, not a side effect.**
/// Nothing is dropped here. A caller that arrives while the breaker is open
/// WAITS for the probe slot, spending its own budget — a learner's speech is
/// irreplaceable and there is no second copy, so the device is patient. What
/// falls off the end of the caller's own retry budget is recorded by the caller
/// as a chunk that was captured and lost, never as one that held no speech.
///
/// One instance per backend budget, shared process-wide: a device can have
/// several accounts signed in and they all point at the same choreographer, so
/// a per-account gate would cap nothing. This bounds ONE DEVICE. A fleet-wide
/// concurrency limit can only come from the server.
class CallUploadGate {
  CallUploadGate({
    this.maxInFlight = defaultMaxInFlight,
    this.failuresToOpen = defaultFailuresToOpen,
    this.openFor = defaultOpenFor,
    this.isServerFailure = choreoUnderPressure,
  }) : assert(maxInFlight > 1, 'a device is never pinned to one upload'),
       assert(failuresToOpen > 0);

  /// How many uploads this device may be waiting on at once.
  ///
  /// Sized against the WORST chunk cadence, not the best. `PcmChunker` caps a
  /// chunk by bytes as well as by time, and the tap reports the format the
  /// device actually captured — 48 kHz is routine on Android — so at 48 kHz
  /// stereo the byte ceiling cuts a chunk every fifteen seconds rather than
  /// every forty-five. Against a thirty-second attempt that is two in steady
  /// state, plus the tail the end of a call flushes: three.
  ///
  /// Never one. Pinning a device to a single upload to make this state
  /// authoritative is forbidden here, and it would serialise that tail behind a
  /// retry for no gain.
  static const defaultMaxInFlight = 3;

  /// Consecutive server-classified failures before the breaker opens.
  ///
  /// Each of those is a whole request that either failed with a 5xx or burned up
  /// to thirty seconds, so three in a row is not a blip on one connection.
  static const defaultFailuresToOpen = 3;

  /// How long the breaker stays open before it will admit a probe.
  ///
  /// Bounded above by the caller's attempt budget — 30s in `CallCaptureService`
  /// — so that ONE waiting attempt can outlast a whole cooldown and take the
  /// probe slot. A cooldown longer than the attempt would mean every attempt
  /// died at admission and the breaker was only ever probed by luck.
  static const defaultOpenFor = Duration(seconds: 15);

  /// The gate every call upload on this device goes through.
  static final CallUploadGate shared = CallUploadGate();

  final int maxInFlight;
  final int failuresToOpen;
  final Duration openFor;

  /// Which failures are evidence about the SERVER. Injected so a test can drive
  /// the breaker without constructing HTTP failures.
  final bool Function(Object error) isServerFailure;

  int _inFlight = 0;

  /// Callers queued for a permit, in arrival order.
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  int _consecutiveFailures = 0;

  /// While non-null and in the future, the breaker is open until then. Null
  /// means closed; a value in the past means half-open and awaiting a probe.
  DateTime? _openUntil;

  /// Completes when the probe currently in flight settles, so other callers can
  /// wait for its verdict instead of polling for one.
  Completer<void>? _probe;

  /// Whether the breaker is currently refusing to let work through.
  bool get isOpen {
    final until = _openUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  @visibleForTesting
  int get inFlight => _inFlight;

  @visibleForTesting
  int get consecutiveFailures => _consecutiveFailures;

  /// Runs [work] under the cap and the breaker.
  ///
  /// [within] is the caller's WHOLE budget for this attempt, waiting included:
  /// time spent queued for a permit or held behind an open breaker is time the
  /// attempt has spent, and pretending otherwise would let one attempt run for
  /// the cooldown plus the request. Null means the caller accepted an unbounded
  /// wait; every production caller passes one.
  ///
  /// A [TimeoutException] can come out of this for two different reasons, and
  /// the gate treats them as opposites even though the caller cannot tell them
  /// apart by type. [work] ran and did not answer in time: that is the server,
  /// and it counts towards the breaker. Or the budget ran out before [work]
  /// started at all: nothing reached the server, so it is not evidence about the
  /// server, and it is recorded nowhere — a breaker that counted its own
  /// refusals would hold itself open for ever with nothing able to close it.
  ///
  /// A PRECONDITION ON [work], because this gate cannot supply it: **[work] must
  /// be safe to run again after this has given up on it.** Giving up is only
  /// this device deciding to stop waiting — nothing here can abort a request in
  /// flight, and there is no idempotency key to send — so a [work] abandoned at
  /// the budget can still reach the server and succeed while its retry succeeds
  /// too. A caller for which that is two of anything must not use this gate.
  /// What makes today's one caller safe is set out in the permit note below.
  Future<T> run<T>(Future<T> Function() work, {Duration? within}) async {
    final deadline = within == null ? null : DateTime.now().add(within);
    final probing = await _admit(deadline);
    try {
      final left = _remaining(deadline);
      if (left != null && left <= Duration.zero) {
        // Outside the block below on purpose: see the refusal note above.
        throw TimeoutException('call upload gate: no budget left to send');
      }
      try {
        final result = await (left == null ? work() : work().timeout(left));
        _recordSuccess(wasProbe: probing);
        return result;
      } catch (error) {
        _recordFailure(error, wasProbe: probing);
        rethrow;
      }
    } finally {
      // Released when we stop WAITING, not when the request truly finishes.
      // Nothing this app sends is abortable — `Requests.post` goes through the
      // top-level `http.post`, and `package:http`'s `AbortableRequest` is not
      // wired into it — so a timed-out upload keeps its socket, and what this
      // cap counts is "uploads this device is still waiting on", NOT "sockets
      // the OS still holds". Both readings are worth having; only the first is
      // available without changing the app's shared HTTP path.
      //
      // Tying the permit to the raw future instead would stall the device
      // rather than wedge it — production reaches `SpeechToTextRepo`, whose own
      // fetch is bounded at sixty seconds — but a stall of thirty seconds per
      // timed-out attempt, on a cap of three, is a stall this feature cannot
      // afford. The injected transcriber is a bare typedef with no deadline of
      // its own, so a caller that supplies an unbounded one would wedge for
      // good; the test uses exactly that.
      //
      // WHAT THAT COSTS, AND WHY IT IS AFFORDABLE HERE. An abandoned upload can
      // still land, so its retry can be a second real delivery of the same
      // chunk — and a learner credited twice for saying something once is the
      // exact harm the recorder election exists to prevent. This gate cannot
      // close that on its own: it has no abort and no idempotency key, and
      // adding one means changing the app's shared HTTP path and the route's
      // contract with it. It is closed one and two layers up instead, and only
      // because every layer is keyed by the chunk rather than by the attempt:
      //
      //  - `CallTranscriptSink` holds each result at `_byIndex[chunk.index]`
      //    and builds each chunk's constructs once per index, so a second
      //    answer overwrites the first rather than adding to it. Credit is
      //    counted per chunk, and a chunk is one slot. Asserted directly, in
      //    call_transcript_sink_test.dart: "a chunk is transcribed once however
      //    often it is delivered" and "a use is built once and never rebuilt".
      //  - `SpeechToTextRepo` (through `BaseRepo`) keys by a sha256 of the
      //    audio: a retry issued while the first request is still running joins
      //    that request instead of making a second one, and one issued after it
      //    succeeded is served from the ten-minute cache. So in production the
      //    second delivery is usually not a second upload either.
      //
      // Recorded here rather than left to be rediscovered, because it is a
      // property of the CALLERS that this object depends on and cannot check.
      // The precondition on [run] states it as the requirement it is. There is
      // no test of it HERE, and there cannot be a useful one: a caller that
      // stopped waiting never sees the abandoned answer, so from this side the
      // second landing is invisible whether it is counted twice or not.
      _settleProbe(probing);
      _releasePermit();
    }
  }

  /// Clears every bit of state. For tests only: a shared gate that carried a
  /// held permit or an open breaker from one test into the next would make the
  /// next one fail for a reason it has nothing to do with.
  @visibleForTesting
  void reset() {
    _inFlight = 0;
    for (final waiter in _waiting) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _waiting.clear();
    _consecutiveFailures = 0;
    _openUntil = null;
    final probe = _probe;
    _probe = null;
    if (probe != null && !probe.isCompleted) probe.complete();
  }

  @visibleForTesting
  static void resetShared() => shared.reset();

  /// Takes a permit and clears the breaker, returning whether this caller was
  /// admitted as THE probe.
  Future<bool> _admit(DateTime? deadline) async {
    await _acquirePermit(deadline);
    try {
      return await _passBreaker(deadline);
    } catch (_) {
      // The permit is ours and nothing else can give it back.
      _releasePermit();
      rethrow;
    }
  }

  Future<void> _acquirePermit(DateTime? deadline) async {
    // Queued callers go first even when a permit is free, or a caller that has
    // been waiting a minute loses to one that arrived this instant.
    if (_waiting.isEmpty && _inFlight < maxInFlight) {
      _inFlight++;
      return;
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    try {
      await _wait(waiter.future, deadline);
    } on TimeoutException {
      // Explicitly, because `Future.timeout` only stops US waiting — it leaves
      // the completer in the queue, where the next release would hand it a
      // permit that nobody is left to give back.
      _waiting.remove(waiter);
      rethrow;
    }
    // No increment: the permit was transferred by [_releasePermit], never
    // created here, or two callers would both count the same one.
  }

  void _releasePermit() {
    while (_waiting.isNotEmpty) {
      final next = _waiting.removeFirst();
      if (!next.isCompleted) {
        next.complete();
        return;
      }
      // Already gave up. Its permit goes to the one behind it rather than being
      // dropped, which is what would shrink the cap by one for the rest of the
      // process.
    }
    // Guarded because [reset] can zero the count under a caller that is still
    // holding one. Nothing else can drive this below zero.
    if (_inFlight > 0) _inFlight--;
  }

  Future<bool> _passBreaker(DateTime? deadline) async {
    while (true) {
      final until = _openUntil;
      if (until == null) return false;
      final now = DateTime.now();
      if (!now.isBefore(until)) {
        final probe = _probe;
        if (probe == null) {
          // Claimed synchronously, with no await between the check and the
          // claim, so two callers cannot both become the probe.
          _probe = Completer<void>();
          return true;
        }
        // Somebody else is probing. Their answer is the answer for everyone, so
        // wait for it rather than asking the server a second time.
        await _wait(probe.future, deadline);
        continue;
      }
      await _wait(Future<void>.delayed(until.difference(now)), deadline);
    }
  }

  void _settleProbe(bool probing) {
    if (!probing) return;
    final probe = _probe;
    _probe = null;
    if (probe != null && !probe.isCompleted) probe.complete();
  }

  void _recordSuccess({required bool wasProbe}) {
    if (!wasProbe && _openUntil != null) {
      // Already in flight when somebody else opened the breaker. It is not the
      // probe, and it says nothing about the state that opened it -- the
      // requests that failed did so AFTER this one was admitted. Letting it
      // close the breaker would admit every waiter with no cooldown at all,
      // which is the one thing the breaker exists to impose; letting it merely
      // clear the failure count would be worse still, because the probe that
      // followed could then fail without reaching the threshold again and the
      // doors would stay open on a backend that is still down.
      //
      // So it changes nothing. Whether the server is well is decided by the
      // probe, which is what the cooldown is for.
      return;
    }
    _consecutiveFailures = 0;
    _openUntil = null;
  }

  /// ONLY A FAILURE THE CLASSIFIER CALLS PRESSURE MAY SPEND ADMISSION BUDGET.
  /// Opening the breaker, and extending it, both cost the learner a cooldown in
  /// which speech that has no second copy cannot be sent — so the evidence for
  /// either has to be evidence [isServerFailure] actually counts. The one
  /// exception is the PROBE, whose job is not to be pressure but to answer the
  /// question the cooldown was opened to ask.
  void _recordFailure(Object error, {required bool wasProbe}) {
    if (isServerFailure(error)) {
      _consecutiveFailures++;
    } else if (_openUntil == null) {
      // CONSECUTIVE means consecutive. A 4xx is the server answering, which is
      // evidence it is alive, so 503-400-503 is not a run of two and must not
      // open a breaker set to two. Leaving the count untouched here made the
      // word in the docs a lie and would have opened the breaker on a backend
      // that was answering perfectly well between two blips.
      //
      // Only while CLOSED. A PROBE that comes back 4xx did not succeed, and
      // clearing the count there would throw the doors open on a backend still
      // down — which is the one thing the probe exists to prevent.
      _consecutiveFailures = 0;
    } else if (!wasProbe) {
      // Open, not the probe, and not pressure: an upload admitted while the
      // breaker was still shut, answering now with a 4xx. Falling through to
      // the re-open below did not merely decide nothing — it bought a whole
      // fresh cooldown with a request the line above had just refused to count,
      // so one malformed chunk of the learner's could hold their own speech
      // back another window, and a trickle of late 4xx answers could hold it
      // back indefinitely.
      //
      // Only the NON-pressure half is dropped, and the asymmetry against
      // [_recordSuccess] — which ignores a non-probe SUCCESS entirely — is
      // deliberate. A 5xx from that same older upload is the server failing
      // now, whenever it was admitted, and it counts; a success is only
      // evidence about a moment that has passed, and the probe is what decides
      // whether the server is well. Both errors lean the same way: towards
      // leaving the server alone.
      return;
    }
    // This also re-opens after a failed PROBE, whatever it failed with, and
    // that is why the clause above excludes the probe rather than testing the
    // error again. A probe only ever runs while the breaker is open, neither
    // branch above can lower the count under it, and the only other thing that
    // lowers it is a SUCCESS — which closes the breaker at the same moment. So
    // a probe that did not succeed always finds the count still at or past the
    // threshold, and a fresh cooldown is the right answer: the server was asked
    // and did not answer well.
    if (_consecutiveFailures >= failuresToOpen) {
      _openUntil = DateTime.now().add(openFor);
    }
  }

  Duration? _remaining(DateTime? deadline) =>
      deadline?.difference(DateTime.now());

  Future<void> _wait(Future<void> settled, DateTime? deadline) {
    final left = _remaining(deadline);
    if (left == null) return settled;
    if (left <= Duration.zero) {
      return Future<void>.error(
        TimeoutException('call upload gate: budget spent waiting'),
        StackTrace.current,
      );
    }
    return settled.timeout(left);
  }
}
