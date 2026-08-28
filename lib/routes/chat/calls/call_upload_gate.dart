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

/// Bounds what this DEVICE has in flight to the choreographer, and stops it
/// hammering one that is already failing.
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
/// probe, and whether IT succeeds decides. The probe is a real chunk upload:
/// there is no synthetic prober and no background timer, so a device with
/// nothing to send makes no requests at all.
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
        _recordSuccess();
        return result;
      } catch (error) {
        _recordFailure(error);
        rethrow;
      }
    } finally {
      // Released when we stop WAITING, not when the request truly finishes.
      // Nothing this app sends is abortable — `Requests.post` goes through the
      // top-level `http.post`, which has no cancellation wired — so a timed-out
      // upload keeps its socket. Tying the permit to that future would leak one
      // per timeout and wedge the device for good after three. The honest
      // reading of this cap is "uploads this device is still waiting on", not
      // "sockets the OS still holds".
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

  void _recordSuccess() {
    _consecutiveFailures = 0;
    _openUntil = null;
  }

  void _recordFailure(Object error) {
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
    }
    // This also re-opens after a failed PROBE, and deliberately without a
    // separate `wasProbe` clause. A probe only ever runs while the breaker is
    // open, the branch above cannot lower the count there, and the only other
    // thing that lowers it is a SUCCESS — which closes the breaker at the same
    // moment. So a probe that did not succeed always finds the count still at
    // or past the threshold, whatever it failed with, and a `wasProbe ||` in
    // front of this would be a condition no test could tell apart from its
    // absence. The guarantee it was there to state — a failed probe never
    // throws the doors open, not even on a 4xx — is asserted directly instead.
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
