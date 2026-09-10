import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_recordings_load.dart';

/// [CallRecordingsLoadController]'s loading machine (design spec section 3):
/// a pure resolver total over (reads in flight?) x (halves present?) x
/// (merge present?) x (grace elapsed?), plus a stateful shell that stamps a
/// grace timestamp off a real clock and re-evaluates on every fed input.
///
/// Every controller test drives a FAKE clock and a FAKE one-shot timer
/// scheduler (see [_FakeClock]/[_FakeTimer], mirroring
/// `call_audio_merge_coordinator_test.dart`'s own `_Scheduler`/`_FakeTimer`
/// simplified to one-shot only), so a grace window's own expiry is provable
/// without a real wait. Where the task names a specific mutation, the
/// comment on the test below names it and the assertion that catches it.

const _grace = Duration(seconds: 30);
const _oneMs = Duration(milliseconds: 1);

void main() {
  group('resolveCallRecordingsLoadState', () {
    test('reads in flight -> loading, regardless of every other input', () {
      expect(
        resolveCallRecordingsLoadState(
          readsInFlight: true,
          halfCount: 0,
          hasMerge: false,
          graceElapsed: false,
        ),
        CallRecordingsLoadState.loading,
      );
      // Precedence: readsInFlight wins even when every other input already
      // looks terminal (a merge present, grace elapsed) -- a fresh read must
      // never be masked by stale halfCount/hasMerge left from a previous
      // call.
      expect(
        resolveCallRecordingsLoadState(
          readsInFlight: true,
          halfCount: 2,
          hasMerge: true,
          graceElapsed: true,
        ),
        CallRecordingsLoadState.loading,
      );
    });

    test('reads done + merge present -> ready, regardless of halves/grace', () {
      expect(
        resolveCallRecordingsLoadState(
          readsInFlight: false,
          halfCount: 0,
          hasMerge: true,
          graceElapsed: false,
        ),
        CallRecordingsLoadState.ready,
      );
      // Precedence: hasMerge wins even once grace has already elapsed -- the
      // resolver-level half of the "one accepted flash" (unavailable ->
      // ready) the spec calls for.
      expect(
        resolveCallRecordingsLoadState(
          readsInFlight: false,
          halfCount: 2,
          hasMerge: true,
          graceElapsed: true,
        ),
        CallRecordingsLoadState.ready,
      );
    });

    test(
      'reads done + zero halves -> none IMMEDIATELY, before grace elapses',
      () {
        // The exact case spec g2 calls out as having fallen through the
        // original `data ?? const []` handling: zero halves must not sit in
        // pendingMerge waiting out a grace nothing will ever fill.
        //
        // Mutation: drop the `halfCount == 0` branch (so a zero-half call
        // falls through to the grace check) -> this returns pendingMerge
        // instead of none -> RED.
        expect(
          resolveCallRecordingsLoadState(
            readsInFlight: false,
            halfCount: 0,
            hasMerge: false,
            graceElapsed: false,
          ),
          CallRecordingsLoadState.none,
        );
      },
    );

    test('reads done + zero halves -> none even once grace has elapsed', () {
      expect(
        resolveCallRecordingsLoadState(
          readsInFlight: false,
          halfCount: 0,
          hasMerge: false,
          graceElapsed: true,
        ),
        CallRecordingsLoadState.none,
      );
    });

    test('reads done + >=1 half + no merge + grace elapsed -> unavailable', () {
      for (final halfCount in [1, 2, 3]) {
        expect(
          resolveCallRecordingsLoadState(
            readsInFlight: false,
            halfCount: halfCount,
            hasMerge: false,
            graceElapsed: true,
          ),
          CallRecordingsLoadState.unavailable,
          reason: 'halfCount=$halfCount',
        );
      }
    });

    test(
      'reads done + >=1 half + no merge + grace NOT elapsed -> pendingMerge',
      () {
        for (final halfCount in [1, 2, 3]) {
          expect(
            resolveCallRecordingsLoadState(
              readsInFlight: false,
              halfCount: halfCount,
              hasMerge: false,
              graceElapsed: false,
            ),
            CallRecordingsLoadState.pendingMerge,
            reason: 'halfCount=$halfCount',
          );
        }
      },
    );
  });

  group('CallRecordingsLoadController', () {
    test('starts in loading before any update() call', () {
      final h = _Harness();
      expect(h.controller.state.value, CallRecordingsLoadState.loading);
    });

    test('the constructor defaults grace to kCallMergeGrace when not '
        'overridden', () {
      // Pinned INDEPENDENTLY of `kCallMergeGrace` itself: if the clock
      // advances below were derived FROM `kCallMergeGrace` (as an earlier
      // version of this test did), then changing that constant's own value
      // would move the constructor's default AND this test's own timing
      // together, and the test would keep passing no matter what the
      // constant actually equals. Spec section 3 (D1) calls for "~30s", so
      // that is the literal, independent value pinned here.
      expect(kCallMergeGrace, const Duration(seconds: 30));

      // Deliberately NOT going through `_Harness`, which always passes an
      // explicit `grace:` (even when using its own default `_grace`
      // constant) and so never actually exercises the CONTROLLER's own
      // default-parameter value -- only a construction that omits `grace`
      // entirely does that.
      final clock = _FakeClock();
      final controller = CallRecordingsLoadController(
        now: clock.now,
        scheduleTimer: clock.schedule,
      );
      addTearDown(controller.dispose);

      controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      expect(controller.state.value, CallRecordingsLoadState.pendingMerge);

      // Mutation: change the constructor's `this.grace = kCallMergeGrace`
      // default to some other hardcoded value -> this still-armed timer
      // fires at the wrong instant relative to the INDEPENDENT 30-second
      // expectation below -> RED. (A change to `kCallMergeGrace`'s own
      // value is caught by the explicit `expect` above instead, precisely
      // because these two advances are hardcoded, not derived from that
      // constant.)
      clock.advance(const Duration(seconds: 30) - _oneMs);
      expect(controller.state.value, CallRecordingsLoadState.pendingMerge);
      clock.advance(_oneMs);
      expect(controller.state.value, CallRecordingsLoadState.unavailable);
    });

    test('state cannot be downcast to the underlying ValueNotifier to write '
        '.value directly, bypassing the disposal-safety machinery', () {
      final h = _Harness();
      // A caller holding only the declared `ValueListenable` static type
      // could still, at runtime, attempt `(controller.state as
      // ValueNotifier<CallRecordingsLoadState>).value = ...` -- writing
      // straight to the inner notifier, triggering its `notifyListeners()`
      // with `_evaluating` still false (that write never goes through
      // `_reevaluate` at all), unprotected by the entire
      // `_teardownDeferred` mechanism a listener-triggered `dispose()`
      // relies on. This is only closed if `state`'s RUNTIME object is not
      // actually a `ValueNotifier` at all.
      //
      // Mutation: change `state`'s getter back to `_stateNotifier` (the
      // concrete notifier itself, merely typed as `ValueListenable`) ->
      // `isA<ValueNotifier<...>>()` succeeds -> RED.
      expect(
        h.controller.state,
        isNot(isA<ValueNotifier<CallRecordingsLoadState>>()),
      );
    });

    test('the controller itself is not a Listenable -- there is no inherited '
        'notifyListeners()/addListener() surface on it to exploit', () {
      final h = _Harness();
      // If this controller extended `ChangeNotifier`, an external caller
      // could write `controller.addListener(controller.dispose);
      // controller.notifyListeners();` -- both PUBLIC, CALLABLE methods
      // regardless of `notifyListeners`'s `@protected` annotation, which
      // is an analyzer hint, not a language access restriction -- and
      // reach `dispose()` from inside `this`'s own notification, hitting
      // the exact disposal-during-notification hazard the rest of this
      // class exists to keep `_stateNotifier` safe from, but for `this`
      // instead. `final` alone does not close this (it only blocks
      // subclassing, not calling an inherited method on an existing
      // instance) -- only NOT extending `ChangeNotifier`/`Listenable` at
      // all does.
      //
      // Mutation: make `CallRecordingsLoadController` extend
      // `ChangeNotifier` again -> `isA<Listenable>()` succeeds -> RED.
      expect(h.controller, isNot(isA<Listenable>()));
    });

    test('a throwing state listener does not leak the underlying notifier '
        'through FlutterErrorDetails.informationCollector', () {
      final h = _Harness();
      h.controller.state.addListener(() {
        throw StateError('a caller-registered listener with its own bug');
      });

      // Flutter's own `ChangeNotifier.notifyListeners()` catches a
      // throwing listener and reports it with an `informationCollector`
      // that attaches the notifying object ITSELF (a
      // `DiagnosticsProperty<ChangeNotifier>` pointing at the real
      // `_stateNotifier`) -- a caller with a global `FlutterError.onError`
      // handler that inspects it could recover a live reference to the
      // real notifier that way, bypassing `state`'s read-only wrapper
      // entirely without ever needing a direct downcast.
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      try {
        h.controller.update(
          readsInFlight: false,
          halfCount: 1,
          hasMerge: false,
        );
      } finally {
        FlutterError.onError = previousOnError;
      }

      // The exception is still reported (not silently swallowed) ...
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<StateError>());
      // ... but through a report that carries no `informationCollector`
      // at all, since it never reached `_stateNotifier`'s OWN
      // `notifyListeners()` catch block in the first place.
      //
      // Mutation: change `_ReadOnlyValueListenable.addListener` back to
      // forwarding `listener` directly (`_inner.addListener(listener)`)
      // instead of wrapping it -> the throw reaches `_inner`'s own catch
      // block -> `informationCollector` is no longer null -> RED.
      expect(reported.single.informationCollector, isNull);
    });

    test('a BROKEN FlutterError.onError does not reopen the leak the fix '
        'above closes', () {
      final h = _Harness();
      h.controller.state.addListener(() {
        throw StateError('a caller-registered listener with its own bug');
      });

      // `FlutterError.reportError` does not guard its own call to
      // `FlutterError.onError` (`onError?.call(details);`, no try/catch --
      // confirmed against this project's pinned Flutter SDK,
      // `foundation/assertions.dart`), so a global handler that itself
      // throws propagates that throw straight back out of the wrapper's own
      // reporting attempt above. This `onError` records every report it
      // receives, but throws back out on the FIRST one only -- exactly the
      // shape a broken error-tracking integration could take, and precisely
      // controlled so this test itself cannot be taken down by its own
      // simulated failure.
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        reported.add(details);
        if (reported.length == 1) {
          throw StateError('onError itself is broken');
        }
      };
      try {
        h.controller.update(
          readsInFlight: false,
          halfCount: 1,
          hasMerge: false,
        );
      } finally {
        FlutterError.onError = previousOnError;
      }

      // With the wrapping closure's own reporting call correctly guarded,
      // that throw is swallowed right there: the wrapping closure itself
      // never throws, so `_inner`'s own `notifyListeners()` never sees this
      // listener fail and never gets a chance to build its OWN,
      // `_inner`-exposing report. Exactly one report happens -- the
      // wrapper's own first, doomed attempt -- not two.
      //
      // Mutation: drop the inner try/catch around the `FlutterError.
      // reportError` call inside the wrapping closure -> the broken
      // `onError`'s throw escapes that closure -> `_inner.notifyListeners()`
      // catches the closure itself throwing and reports IT via a SECOND,
      // `_inner`-exposing `FlutterErrorDetails` (`onError`'s second call, at
      // `reported.length == 2`, does not throw, so nothing here crashes
      // uncontrolled) -> `reported` reads length 2 instead of 1 -> RED.
      expect(reported, hasLength(1));
    });

    test('removeListener still removes the correct listener by identity after '
        'the wrapping addListener requires for the throw-safety fix above', () {
      final h = _Harness();
      var callCount = 0;
      void listener() => callCount++;

      h.controller.state.addListener(listener);
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      expect(callCount, 1);

      h.controller.state.removeListener(listener);
      // Mutation: make `removeListener` a no-op (or forward the wrong
      // reference) -> `listener` keeps firing after removal ->
      // callCount reads 2 below instead of 1 -> RED.
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: true);
      expect(callCount, 1);
    });

    test('addListener after dispose() throws without retaining a stale '
        'entry for a registration that never actually took', () {
      final h = _Harness();
      h.controller.dispose();

      expect(
        () => h.controller.state.addListener(() {}),
        // `_inner` (the real ValueNotifier) throws on `addListener` once
        // disposed -- confirmed against this project's pinned Flutter SDK.
        throwsA(isA<FlutterError>()),
      );
      // Mutation: register into `_wrapped` BEFORE delegating to
      // `_inner.addListener` (the original order) -> `_inner`'s own
      // disposed-assert throws AFTER that map mutation has already
      // happened, leaving a stale entry nothing can ever clean up
      // afterward (`dispose()` is now a permanent no-op) ->
      // debugListenerCount reads 1 instead of 0 -> RED.
      expect(h.controller.debugListenerCount, 0);
    });

    test('adding the same listener twice and removing it twice fully '
        'silences it, matching ValueNotifier\'s own multiplicity contract', () {
      final h = _Harness();
      var callCount = 0;
      void listener() => callCount++;

      h.controller.state.addListener(listener);
      h.controller.state.addListener(listener);
      expect(h.controller.debugListenerCount, 2);

      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      // Registered twice -> fires twice for one notification, matching
      // ValueNotifier's own documented contract ("an additional instance
      // is added, and must be removed the same number of times it is
      // added before it will stop being called").
      expect(callCount, 2);

      h.controller.state.removeListener(listener);
      h.controller.state.removeListener(listener);
      expect(h.controller.debugListenerCount, 0);

      // Mutation: track only the LATEST wrapper per listener key (a plain
      // `Map<VoidCallback, VoidCallback>`, this file's earlier design) ->
      // the second `addListener` above overwrites the map's only entry for
      // `listener` instead of tracking both registrations -> the FIRST
      // `removeListener` above removes the only registration the map
      // still knows about, leaving the OTHER wrapped closure permanently
      // registered on `_inner` with no way for the caller to reach it ->
      // `listener` keeps firing below -> callCount reads 3 instead of 2 ->
      // RED.
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: true);
      expect(callCount, 2);
    });

    test('removing one of two duplicate registrations from WITHIN the '
        'first firing still lets the second, already-in-flight firing '
        'complete in the SAME notification pass', () {
      final h = _Harness();
      var callCount = 0;
      void listener() {
        callCount++;
        if (callCount == 1) {
          h.controller.state.removeListener(listener);
        }
      }

      h.controller.state.addListener(listener);
      h.controller.state.addListener(listener);

      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      // Registered twice; `listener` removes ONE registration of itself
      // from inside its OWN first firing, in the same pass. A real
      // ValueNotifier's own `removeListener` finds and removes (or, during
      // an active notification, nulls) the FIRST matching slot by index --
      // the one whose call has ALREADY been dispatched -- so the SECOND,
      // not-yet-reached slot is unaffected and still fires: `listener`
      // fires TWICE in this pass, not once.
      //
      // Mutation: remove the NEWEST tracked wrapper instead of the OLDEST
      // (`List.removeLast` in `removeListener`, this file's earlier
      // design) -> the NOT-YET-fired registration is the one silenced ->
      // `listener`'s second, already-scheduled firing never happens ->
      // callCount reads 1 instead of 2 -> RED.
      expect(callCount, 2);

      // The removal still genuinely took effect for FUTURE notifications,
      // though: exactly one registration remains.
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: true);
      expect(callCount, 3);
    });

    test('reads-complete + merge present -> ready, no timer armed', () {
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 2, hasMerge: true);
      expect(h.controller.state.value, CallRecordingsLoadState.ready);
      expect(h.clock.scheduledCount, 0);
    });

    test('reads-complete + 1 half + no merge -> pendingMerge, then the timer '
        'fires at grace -> unavailable', () {
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);
      expect(h.clock.scheduledCount, 1);

      h.clock.advance(_grace - _oneMs);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);

      h.clock.advance(_oneMs);
      expect(h.controller.state.value, CallRecordingsLoadState.unavailable);
    });

    test('a fresh refetch cycle (readsInFlight: true) from a NON-terminal '
        'state moves back to loading and cancels the timer', () {
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);
      expect(h.clock.scheduledCount, 1);

      // Mutation: change `_readsInFlight = readsInFlight;` in `update()`
      // to unconditionally assign `false` (ignoring the argument) -> this
      // feed would still resolve `pendingMerge`, never `loading` -> RED.
      // The ONLY other place this suite feeds `readsInFlight: true` to
      // the controller is after `ready` is already latched, where the
      // ready-latch short-circuits before the field is ever read -- this
      // is the one case that actually exercises it against a live,
      // non-terminal resolution.
      h.controller.update(readsInFlight: true, halfCount: 1, hasMerge: false);
      expect(h.controller.state.value, CallRecordingsLoadState.loading);
      expect(h.clock.scheduledCount, 0);
    });

    test('reads-complete + 0 halves -> none immediately, no timer armed', () {
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 0, hasMerge: false);
      expect(h.controller.state.value, CallRecordingsLoadState.none);
      expect(h.clock.scheduledCount, 0);

      // Mutation: arm the timer regardless of the published state (e.g. drop
      // the `published != pendingMerge` check in `_syncTimerFor`) ->
      // scheduledCount would read 1 above -> RED. Waiting the whole grace out
      // changes nothing either way, because nothing was ever coming.
      h.clock.advance(_grace);
      expect(h.controller.state.value, CallRecordingsLoadState.none);
      expect(h.clock.scheduledCount, 0);
    });

    test(
      'a half arriving after an initial zero-halves report still counts down '
      'from when reads first completed, not from when the half arrived',
      () {
        final h = _Harness();
        h.controller.update(
          readsInFlight: false,
          halfCount: 0,
          hasMerge: false,
        );
        expect(h.controller.state.value, CallRecordingsLoadState.none);

        h.clock.advance(const Duration(seconds: 20));
        h.controller.update(
          readsInFlight: false,
          halfCount: 1,
          hasMerge: false,
        );
        expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);

        // Only 10s of the ORIGINAL 30s grace remains, not a fresh 30s from
        // when this half showed up.
        h.clock.advance(const Duration(seconds: 10) - _oneMs);
        expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);
        h.clock.advance(_oneMs);
        expect(h.controller.state.value, CallRecordingsLoadState.unavailable);
      },
    );

    test('a wall-clock correction that jumps BACKWARD during the grace '
        'window never re-arms for MORE than a fresh full grace', () {
      // NOTE on what this test does NOT try to prove: given enough total
      // real time and no FURTHER correction, an unclamped re-arm's own
      // (inflated) due instant and a clamped chain of fresh-grace re-arms
      // both eventually land on the exact same monotonic instant --
      // `grace + correction`, algebraically, either way -- so checking
      // only the EVENTUAL state cannot tell them apart. What genuinely
      // differs, and what actually matters (bounding how long this
      // machine can go without spontaneously re-checking itself, which is
      // the difference between noticing a LATER, correcting clock change
      // within a fresh `grace` and not noticing it for as long as the
      // ORIGINAL correction happened to be), is the re-arm's OWN
      // requested duration -- checked here directly via
      // `_FakeClock.nextDueIn`.
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);
      expect(h.clock.nextDueIn, _grace);

      // The wall clock (what `now()` reports) is corrected BACKWARD by
      // 60s -- larger than the grace itself -- exactly the shape a real
      // NTP step correction or a manual clock change can take. This does
      // not itself fire or reschedule anything: a real `Timer`'s own
      // monotonic scheduling is unaffected by a wall-clock change, which
      // is why `_FakeClock` tracks due instants against a separate
      // monotonic timeline, never against `now()`'s own value (see its
      // own doc).
      h.clock.adjustWallClock(const Duration(seconds: -60));

      // Advancing to the ORIGINAL timer's own due fires it: `now()` reads
      // WELL BEHIND `_graceStartedAt` (the correction was larger than the
      // grace), so re-resolving correctly reports `graceElapsed: false`
      // and the state stays `pendingMerge` -- but the RE-ARM that follows
      // must not request more than a fresh grace's worth of additional
      // waiting.
      h.clock.advance(_grace);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);

      // Mutation: drop the `elapsed.isNegative ? Duration.zero : elapsed`
      // clamp in `_armTimer` (subtract the raw, possibly-negative
      // `elapsed` straight from `grace`) -> by the time this re-arm runs,
      // 30s of REAL progress (the advance above) has already clawed back
      // 30s of the original 60s correction, so `elapsed` here reads -30s,
      // not the full -60s -> this re-arm computes `grace - (-30s) = 60s`
      // of remaining wait, so the NEXT due instant is 60s away instead of
      // a fresh 30s -> `nextDueIn` reads 60s instead of 30s -> RED.
      expect(h.clock.nextDueIn, _grace);
    });

    test('_FakeClock.advance() keeps now() in lockstep with real progress '
        'across MULTIPLE timer firings inside ONE call, not just when they '
        'are one advance() call apart', () {
      // Regression coverage for a bug in this fake's OWN `advance()`,
      // found by an adversarial review of this exact file: an earlier
      // version jumped the fake wall clock straight to the FULL requested
      // target BEFORE firing any intermediate timer due inside that span,
      // so a callback firing PARTWAY through one large `advance()` call
      // could observe `now()` already reflecting time that, from that
      // callback's own point in the sequence, had not actually elapsed
      // yet. A listener that calls `retry()` once, the first time it
      // observes `unavailable`, makes this externally observable:
      // `retry()` re-stamps the grace window to WHATEVER `now()` currently
      // reads, so an inflated `now()` reading at that moment corrupts the
      // fresh window it starts. No wall-clock correction is involved at
      // all here -- this is purely about `advance()`'s own correctness.
      CallRecordingsLoadState runWithChunks(List<Duration> chunks) {
        final h = _Harness();
        var retried = false;
        h.controller.state.addListener(() {
          if (h.controller.state.value == CallRecordingsLoadState.unavailable &&
              !retried) {
            retried = true;
            h.controller.retry();
          }
        });
        h.controller.update(
          readsInFlight: false,
          halfCount: 1,
          hasMerge: false,
        );
        for (final chunk in chunks) {
          h.clock.advance(chunk);
        }
        return h.controller.state.value;
      }

      // Reference result: two separate 30s steps, each landing exactly on
      // a due instant -- this shape was never at risk from the bug above.
      // `retry()` fires at the first `unavailable` (30s in), restamping
      // the grace; a further, genuine 30s then elapses before the SECOND
      // `unavailable`.
      final stepped = runWithChunks([_grace, _grace]);
      expect(stepped, CallRecordingsLoadState.unavailable);

      // Mutation: jump the fake wall clock to the requested target
      // immediately, at the top of `advance`, instead of in lockstep with
      // real progress at each intermediate firing (this fake's own
      // earlier design) -> a SINGLE 60s advance lets the FIRST (30s-due)
      // firing observe `now()` already 60s ahead, so `retry()`'s restamp
      // above is corrupted by 30s of time that has not really passed yet
      // at that point in the sequence -> the second firing (still inside
      // the SAME 60s advance) finds only 0s of the FRESH grace elapsed
      // instead of a genuine 30s -> this single-chunk run reads
      // `pendingMerge` instead of matching the reference result -> RED.
      final singleChunk = runWithChunks([const Duration(seconds: 60)]);
      expect(singleChunk, stepped);
    });

    test(
      'a late merge update moves pendingMerge to ready and cancels the timer',
      () {
        final h = _Harness();
        h.controller.update(
          readsInFlight: false,
          halfCount: 1,
          hasMerge: false,
        );
        expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);
        expect(h.clock.scheduledCount, 1);

        h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: true);
        expect(h.controller.state.value, CallRecordingsLoadState.ready);
        // Mutation: drop the `_cancelTimer()` call at the top of
        // `_syncTimerFor` -> the timer armed by the FIRST update() above is
        // never cancelled when the second one settles at ready (which does
        // not arm a replacement, since `ready != pendingMerge`) ->
        // scheduledCount reads 1 instead of 0 -> RED. This IS the proof
        // that the old timer was genuinely cancelled: with it already
        // confirmed absent here, advancing the clock further would have
        // nothing left to fire, so no further check adds information --
        // `ready`'s own latch would read the same either way regardless of
        // whether cancellation had genuinely happened, which is exactly
        // why that was not used as the proof.
        expect(h.clock.scheduledCount, 0);
      },
    );

    test('a late merge update moves UNAVAILABLE to ready (the one accepted '
        'flash)', () {
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      h.clock.advance(_grace);
      expect(h.controller.state.value, CallRecordingsLoadState.unavailable);

      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: true);
      expect(h.controller.state.value, CallRecordingsLoadState.ready);
    });

    test('a late half within grace stays pendingMerge, without resetting the '
        'countdown', () {
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      h.clock.advance(const Duration(seconds: 20));

      h.controller.update(readsInFlight: false, halfCount: 2, hasMerge: false);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);

      // Only 10s of the ORIGINAL grace remains -- the late half must not
      // have granted a fresh 30s.
      h.clock.advance(const Duration(seconds: 10) - _oneMs);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);
      h.clock.advance(_oneMs);
      expect(h.controller.state.value, CallRecordingsLoadState.unavailable);
    });

    test('late data never regresses a terminal ready', () {
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 2, hasMerge: true);
      expect(h.controller.state.value, CallRecordingsLoadState.ready);

      // Mutation: remove the `ready` latch in `_publishOnce` (always
      // resolve fresh from the live fields) -> this call would drop the
      // state to `none` -> RED.
      h.controller.update(readsInFlight: false, halfCount: 0, hasMerge: false);
      expect(h.controller.state.value, CallRecordingsLoadState.ready);

      // Also proven against reads going back "in flight" (e.g. a caller that
      // re-triggers a fetch without going through retry()).
      h.controller.update(readsInFlight: true, halfCount: 0, hasMerge: false);
      expect(h.controller.state.value, CallRecordingsLoadState.ready);
      expect(h.clock.scheduledCount, 0);
    });

    test('retry() resets the grace to a fresh full window', () {
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      h.clock.advance(_grace);
      expect(h.controller.state.value, CallRecordingsLoadState.unavailable);

      h.controller.retry();
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);
      expect(h.clock.scheduledCount, 1);

      // A FRESH grace, not the already-elapsed one: advancing to just under
      // another full window must not yet flip back to unavailable.
      h.clock.advance(_grace - _oneMs);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);
      h.clock.advance(_oneMs);
      expect(h.controller.state.value, CallRecordingsLoadState.unavailable);
    });

    test(
      'retry() alone does not change readsInFlight/halfCount/hasMerge -- the '
      'caller still drives those through update()',
      () {
        final h = _Harness();
        h.controller.update(
          readsInFlight: false,
          halfCount: 0,
          hasMerge: false,
        );
        expect(h.controller.state.value, CallRecordingsLoadState.none);

        // Not the button's real trigger state, but the contract must hold
        // regardless: retrying a `none` changes nothing, since it is still
        // zero halves.
        h.controller.retry();
        expect(h.controller.state.value, CallRecordingsLoadState.none);
        expect(h.clock.scheduledCount, 0);
      },
    );

    test('the very first update(), already reporting reads complete, still '
        'stamps grace correctly', () {
      // No prior update(readsInFlight: true, ...) call at all -- the
      // controller's own true->false edge detection must still fire on
      // this FIRST call, off its assumed initial "in flight" baseline.
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);

      h.clock.advance(_grace - _oneMs);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);
      h.clock.advance(_oneMs);
      expect(h.controller.state.value, CallRecordingsLoadState.unavailable);
    });

    test('no notify after dispose', () {
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);

      var notifyCount = 0;
      h.controller.state.addListener(() => notifyCount++);

      h.controller.dispose();
      // dispose() itself must cancel the timer it leaves pending.
      expect(h.clock.scheduledCount, 0);

      // A post-dispose update that would RESOLVE TO THE SAME state
      // (pendingMerge again) must not arm a fresh timer either. For this
      // particular, non-reentrant "call long after a plain dispose()"
      // shape, EITHER `update()`'s own entry guard OR `_reevaluate`'s own
      // guard (right after publishing -- see its doc) independently
      // suffices, so removing just one of the two, with the other intact,
      // is NOT observable via this specific sequence (verified: neither
      // mutation flips this assertion red on its own). What this proves is
      // the outward CONTRACT -- nothing observable happens, ever, once
      // disposed -- regardless of which guard is doing the work for this
      // particular call shape. `_reevaluate`'s guard is the one genuinely
      // load-bearing check overall: it is independently proven necessary by
      // the "listener that calls dispose() synchronously" test above, whose
      // REENTRANT-during-publish shape is the one case `update()`'s own
      // entry guard cannot reach (that call has already passed its own
      // check before dispose() is even triggered).
      expect(
        () => h.controller.update(
          readsInFlight: false,
          halfCount: 3,
          hasMerge: false,
        ),
        returnsNormally,
      );
      expect(h.clock.scheduledCount, 0);

      // A post-dispose update that would resolve to a DIFFERENT state
      // (ready) must not publish it or notify listeners either -- the
      // outward half of the same contract, this time for the write
      // `_setState`'s own leaf guard exists to stop (it would otherwise
      // throw, "A ValueNotifier was used after being disposed").
      expect(
        () => h.controller.update(
          readsInFlight: false,
          halfCount: 3,
          hasMerge: true,
        ),
        returnsNormally,
      );
      expect(notifyCount, 0);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);
      expect(h.clock.scheduledCount, 0);
    });

    test('dispose() cancels a pending grace timer', () {
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      expect(h.clock.scheduledCount, 1);

      h.controller.dispose();
      expect(h.clock.scheduledCount, 0);
    });

    test('dispose() (the immediate, non-reentrant path) releases every '
        'listener state was holding, not just the underlying notifier\'s '
        'own list', () {
      final h = _Harness();
      h.controller.state.addListener(() {});
      h.controller.state.addListener(() {});
      expect(h.controller.debugListenerCount, 2);

      // The immediate path: `dispose()` called from OUTSIDE any
      // `_reevaluate` call, same as an ordinary widget's own
      // `State.dispose()` -- `_evaluating` is false here, so this goes
      // straight through `dispose()`'s `else` branch rather than the
      // deferred one (see the sibling test below for that one).
      h.controller.dispose();

      // Mutation: drop the `_stateWrapper._releaseListeners()` call from
      // `dispose()`'s `else` branch -> the map still holds both closures
      // (and anything they capture) reachable through `state` for as long
      // as this controller itself stays reachable, even though
      // `_stateNotifier`'s OWN listener list has already been cleared by
      // its own `dispose()` a line above -> RED.
      expect(h.controller.debugListenerCount, 0);
    });

    // Reentrancy: `_setState` publishes through a `ValueNotifier`, which
    // calls every listener SYNCHRONOUSLY before the publishing call
    // resolves -- so a listener that reacts to a state change by calling
    // back into the controller runs INSIDE the outer evaluation, not after
    // it. Found by an adversarial Codex review of this file: without
    // coalescing, both the outer and the reentrant call independently call
    // `_armTimer`, each overwriting `_timer` with its own handle and
    // orphaning the other -- a real, live timer neither `dispose()` nor any
    // later evaluation ever cancels.

    test('a listener that calls retry() synchronously off a state publish does '
        'not leak the timer the outer evaluation also arms', () {
      final h = _Harness();
      var retriedOnce = false;
      h.controller.state.addListener(() {
        if (h.controller.state.value == CallRecordingsLoadState.pendingMerge &&
            !retriedOnce) {
          retriedOnce = true;
          h.controller.retry();
        }
      });

      // loading -> pendingMerge is a real value change, so this WILL
      // notify the listener above synchronously, from inside this call.
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);

      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);
      expect(retriedOnce, isTrue);
      // Proves the outward contract for this reentrant shape: exactly one
      // timer survives -- NOT that it reflects a freshly-re-stamped grace
      // (this listener reacts to the very FIRST pendingMerge publish, so
      // the reentrant retry() re-stamps at essentially the same instant the
      // original edge already did; there is no meaningful "fresh vs stale"
      // gap for this specific shape to distinguish -- that property is
      // proven properly, with a real clock gap, by the "retry() resets the
      // grace" test instead). `_syncTimerFor`'s own `_cancelTimer()` call is
      // NOT load-bearing for THIS specific assertion, verified: removing it
      // does not flip this test, because the reentrant branch never touches
      // the timer at all (see `_reevaluate`'s own doc) -- `_armTimer` is
      // called exactly ONCE in this whole sequence, by the outer call,
      // against a `_timer` that starts null, so there is nothing already
      // armed for a missing cancel to fail to clean up here. Cancellation
      // IS load-bearing elsewhere -- see the "late merge update... cancels
      // the timer" test's own mutation comment, where a timer really is
      // already armed before the second call needs to replace it.
      expect(h.clock.scheduledCount, 1);
    });

    test('a listener that feeds a merge synchronously off a pendingMerge '
        'publish leaves no timer armed once the state settles at ready', () {
      final h = _Harness();
      var mergedOnce = false;
      h.controller.state.addListener(() {
        if (h.controller.state.value == CallRecordingsLoadState.pendingMerge &&
            !mergedOnce) {
          mergedOnce = true;
          h.controller.update(
            readsInFlight: false,
            halfCount: 1,
            hasMerge: true,
          );
        }
      });

      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);

      expect(h.controller.state.value, CallRecordingsLoadState.ready);
      expect(mergedOnce, isTrue);
      // Mutation (the bug as found, and how it is prevented now): make
      // `_reevaluate`'s outer branch capture `resolved` BEFORE calling
      // `_publishOnce()` and sync the timer against that stale local
      // instead of re-reading `_stateNotifier.value` afterward -> it would
      // still see the pre-reentrancy `pendingMerge` it captured, arming a
      // timer for a state nothing is in anymore -> scheduledCount reads 1
      // right here -> RED. (This is an INCORRECTLY-armed timer, not a
      // permanently orphaned one -- `_timer` still correctly references it,
      // so a later `dispose()` or evaluation would still cancel it via
      // `_cancelTimer()`; the bug is that nothing should have armed it in
      // the first place for a machine already at `ready`, not that it can
      // never be cleaned up.)
      expect(h.clock.scheduledCount, 0);
    });

    // A second adversarial round (independent Codex review) found two more
    // real defects in the FIRST reentrancy fix itself: disposing from
    // inside a notification crashes against Flutter's own
    // `ChangeNotifier.dispose()` assertion, and coalescing multiple
    // reentrant `update()` calls into a single "latest snapshot" pass could
    // silently discard a genuine, if momentary, merge observation. Both are
    // reproduced directly below.

    test('a listener that calls dispose() synchronously off a state publish '
        'does not crash and leaves no timer armed', () {
      final h = _Harness();
      h.controller.state.addListener(() {
        if (h.controller.state.value == CallRecordingsLoadState.pendingMerge) {
          h.controller.dispose();
        }
      });

      // `notifyListeners()` wraps EACH listener call in its own try/catch
      // and reports a thrown exception via `FlutterError.reportError`
      // rather than letting it propagate -- see
      // `foundation/change_notifier.dart`'s own `notifyListeners`. That
      // means a crash inside the listener above would NOT surface as a
      // thrown exception from `update()` below: `returnsNormally` alone
      // cannot see it, it would only ever be a printed, silently-swallowed
      // `FlutterError`. Capturing `FlutterError.onError` around the call is
      // what actually proves no such error was reported.
      final reportedErrors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reportedErrors.add;
      try {
        h.controller.update(
          readsInFlight: false,
          halfCount: 1,
          hasMerge: false,
        );
      } finally {
        FlutterError.onError = previousOnError;
      }
      // Mutation: make `dispose()` always call `_stateNotifier.dispose()`
      // immediately, dropping the `_evaluating`-gated deferral -> tearing it
      // down synchronously from inside its OWN `notifyListeners()` call
      // trips Flutter's own `ChangeNotifier.dispose()` assertion ("was
      // called during the call to notifyListeners()"), which
      // `notifyListeners()`'s own try/catch reports through
      // `FlutterError.reportError` rather than letting propagate ->
      // `reportedErrors` goes non-empty -> RED (verified: this specific
      // mutation does NOT flip `returnsNormally` around the same call,
      // confirming that check alone cannot see this class of failure).
      expect(reportedErrors, isEmpty);
      // Mutation: drop the `if (_disposed) return;` in `_reevaluate` (the
      // one between `_publishOnce` and `_syncTimerFor`) -> `dispose()`'s own
      // `_cancelTimer()` call still runs immediately and unconditionally
      // (it is only the INNER NOTIFIER's teardown that is deferred, not
      // that call), but at the instant it runs `_timer` is still null --
      // the outer call has not reached its own `_armTimer()` yet. THAT
      // call, happening after `dispose()` has already returned, is what
      // arms a timer nothing will now ever cancel (the outer's own
      // timer-sync no longer checks disposal first) -> scheduledCount reads
      // 1 -> RED (verified: this mutation does NOT flip `reportedErrors`,
      // since the deferred `_stateNotifier.dispose()` still only runs
      // safely in `_reevaluate`'s `finally`, outside any notification -- it
      // is a SEPARATE guard from the one above).
      expect(h.clock.scheduledCount, 0);

      // An ordinary second dispose() call -- e.g. the owning widget's own
      // `State.dispose()`, unaware a listener already tore this down --
      // must remain a harmless no-op. This one genuinely can throw straight
      // out to the caller (nothing wraps it in a notify loop), so
      // `returnsNormally` is the right check here.
      expect(() => h.controller.dispose(), returnsNormally);
    });

    test('dispose() (the DEFERRED, reentrant path above) also releases '
        'every listener state was holding', () {
      final h = _Harness();
      h.controller.state.addListener(() {
        if (h.controller.state.value == CallRecordingsLoadState.pendingMerge) {
          h.controller.dispose();
        }
      });
      // A second, ordinary listener alongside the one that disposes --
      // proves this releases EVERY listener the wrapper holds, not just the
      // one that happened to trigger the disposal.
      h.controller.state.addListener(() {});
      expect(h.controller.debugListenerCount, 2);

      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);

      // `dispose()` was called from INSIDE the very notification the state
      // change it reacts to just triggered, so
      // `_stateWrapper._releaseListeners()` cannot run until `_reevaluate`'s
      // own top-level call finishes unwinding (see `dispose()`'s own doc) --
      // this exercises `_reevaluate`'s deferred-teardown branch, not
      // `dispose()`'s own immediate `else` branch the sibling test above
      // (the one right after "dispose() cancels a pending grace timer")
      // already covers.
      //
      // Mutation: drop the `_stateWrapper._releaseListeners()` call from
      // `_reevaluate`'s deferred-teardown branch specifically, leaving the
      // one in `dispose()`'s own immediate branch intact -> this exact
      // REENTRANT disposal shape never releases the map at all -> RED
      // (verified: the immediate-path sibling test does NOT catch this
      // specific mutation, since it never takes the deferred branch at
      // all).
      expect(h.controller.debugListenerCount, 0);
    });

    test('a merge fed reentrantly still latches ready even when a later '
        'reentrant update in the same synchronous burst reports no merge', () {
      final h = _Harness();
      var reacted = false;
      h.controller.state.addListener(() {
        if (h.controller.state.value == CallRecordingsLoadState.pendingMerge &&
            !reacted) {
          reacted = true;
          // A genuine merge arrives...
          h.controller.update(
            readsInFlight: false,
            halfCount: 1,
            hasMerge: true,
          );
          // ...immediately followed, in the SAME synchronous burst, by a
          // second, stale read that still reports no merge. This must not
          // erase the merge already latched a moment ago.
          h.controller.update(
            readsInFlight: false,
            halfCount: 1,
            hasMerge: false,
          );
        }
      });

      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);

      // Mutation (the bug as found): coalescing collapses both reentrant
      // update() calls into ONE pass that resolves against whatever the
      // fields read AFTER both have run (hasMerge back at false), so the
      // momentary `true` is never actually evaluated on its own and the
      // merge is silently lost -> state stays pendingMerge instead of
      // latching ready -> RED.
      expect(h.controller.state.value, CallRecordingsLoadState.ready);
    });
  });
}

// -----------------------------------------------------------------------------
// Fakes: a fully manual clock + one-shot timer scheduler.
// -----------------------------------------------------------------------------

/// A manual one-shot [Timer] handle. [cancel] flips [isActive] false, exactly
/// like a real [Timer] guarantees its callback can never fire once
/// cancelled -- [_FakeClock.advance] relies on that flag rather than any
/// eager list bookkeeping.
class _FakeTimer implements Timer {
  bool _isActive = true;

  @override
  void cancel() => _isActive = false;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => 0;
}

class _Scheduled {
  _Scheduled(this.due, this.callback, this.timer);

  /// A MONOTONIC due instant (elapsed time since this fake's own arbitrary
  /// zero), never a wall-clock [DateTime] -- see [_FakeClock]'s own doc for
  /// why the two must be tracked separately.
  final Duration due;
  final void Function() callback;
  final _FakeTimer timer;
}

/// A fully manual clock + one-shot timer scheduler, standing in for
/// [DateTime.now] and `Timer.new` on the same terms
/// `call_audio_merge_coordinator_test.dart`'s own `_Scheduler`/`_FakeTimer`
/// stand in for [DateTime.now]/`Timer.new` there -- simplified to one-shot
/// only, since [CallRecordingsLoadController] never schedules a periodic
/// timer.
///
/// Tracks TWO separate timelines, not one, so a test can simulate a
/// wall-clock correction (NTP, a manual clock change) independent of real
/// elapsed time -- exactly as a real device can: [_monotonic] is real
/// elapsed time, advanced ONLY by [advance], and is what every scheduled
/// timer's own due instant is measured against (mirroring how a real
/// [Timer] is scheduled against a monotonic clock internally, immune to a
/// wall-clock change happening around it); [_wallClock] is what [now]
/// reports, advanced by [advance] the same way an ordinary, uncorrected
/// wall clock would be, but ALSO independently adjustable by
/// [adjustWallClock] without moving [_monotonic] at all. An earlier version
/// of this fake used a single [DateTime] for both purposes, which could not
/// express a wall-clock correction as anything other than real time itself
/// moving backward -- collapsing the exact distinction
/// `CallRecordingsLoadController._armTimer`'s own clamp exists to handle.
class _FakeClock {
  DateTime _wallClock = DateTime.utc(2026, 1, 1);
  Duration _monotonic = Duration.zero;
  final List<_Scheduled> _scheduled = [];

  DateTime now() => _wallClock;

  /// Counts only still-active (neither fired nor cancelled) timers -- a
  /// direct way for a test to prove "no timer is currently armed" without
  /// reaching into the controller's own private state.
  int get scheduledCount =>
      _scheduled.where((entry) => entry.timer.isActive).length;

  /// The remaining MONOTONIC duration until the earliest still-active
  /// scheduled timer fires, or `null` if none is armed. Lets a test verify
  /// a re-arm's OWN requested duration directly, which the EVENTUAL state
  /// it leads to cannot always distinguish -- see the wall-clock-correction
  /// test's own doc for why an inflated re-arm and a correctly-bounded one
  /// can converge on the exact same final outcome given enough total
  /// advancing, making the re-arm's own duration the only thing that
  /// actually tells them apart.
  Duration? get nextDueIn {
    final activeDueTimes = _scheduled
        .where((entry) => entry.timer.isActive)
        .map((entry) => entry.due);
    if (activeDueTimes.isEmpty) return null;
    final earliest = activeDueTimes.reduce((a, b) => a < b ? a : b);
    return earliest - _monotonic;
  }

  Timer schedule(Duration duration, void Function() callback) {
    final timer = _FakeTimer();
    _scheduled.add(_Scheduled(_monotonic + duration, callback, timer));
    return timer;
  }

  /// Moves BOTH timelines forward by [duration] -- real elapsed time, and
  /// (absent any [adjustWallClock] call) the wall clock right along with
  /// it, exactly like an ordinary, uncorrected clock -- firing every
  /// still-active timer whose due instant falls at or before the new
  /// monotonic time, in due order. A callback that itself schedules a new
  /// timer synchronously (as `CallRecordingsLoadController`'s own
  /// grace-timer callback can, when re-arming) is eligible to fire again
  /// within this same advance if its own due instant still falls inside it.
  ///
  /// [_wallClock] is advanced IN LOCKSTEP with [_monotonic] at each
  /// intermediate firing below, by exactly the step just taken -- NOT
  /// jumped straight to its final value up front. An earlier version of
  /// this method did the latter, which an adversarial review of this
  /// exact file caught: it let a callback firing PARTWAY through a single
  /// large [advance] call observe [now] already reflecting the FULL
  /// requested [duration], including real time that -- from that
  /// callback's own point in the sequence -- has not actually elapsed
  /// yet. That corrupted anything computed FROM [now] at that point (most
  /// concretely, `CallRecordingsLoadController.retry`'s own re-stamp of
  /// its grace window), producing a DIFFERENT, WRONG result depending
  /// purely on how a test happened to CHUNK its [advance] calls -- e.g. a
  /// single 60s [advance] spanning two grace-timer firings disagreeing
  /// with two separate 30s [advance] calls reaching the exact same
  /// due instants, with no clock correction involved at all. Stepping
  /// both timelines together removes that chunking-dependence entirely.
  void advance(Duration duration) {
    final target = _monotonic + duration;
    while (true) {
      _scheduled.removeWhere((entry) => !entry.timer.isActive);
      _Scheduled? next;
      for (final entry in _scheduled) {
        if (entry.due > target) continue;
        if (next == null || entry.due < next.due) next = entry;
      }
      if (next == null) break;
      _wallClock = _wallClock.add(next.due - _monotonic);
      _monotonic = next.due;
      _scheduled.remove(next);
      next.timer._isActive = false;
      next.callback();
    }
    _wallClock = _wallClock.add(target - _monotonic);
    _monotonic = target;
  }

  /// Adjusts ONLY what [now] reports, by [duration] (negative moves it
  /// BACKWARD), without moving real/[_monotonic] time or firing or
  /// rescheduling anything -- simulating a wall-clock correction a real
  /// system clock can undergo (NTP, a manual change, a timezone/DST edge
  /// case) independent of how much real time has actually passed. A real
  /// [Timer], once armed, is unaffected by exactly this kind of change,
  /// which is why this fake's own [_scheduled] due instants are tracked
  /// against [_monotonic], never against [now]'s own value.
  void adjustWallClock(Duration duration) {
    _wallClock = _wallClock.add(duration);
  }
}

// -----------------------------------------------------------------------------
// Harness.
// -----------------------------------------------------------------------------

class _Harness {
  _Harness({Duration grace = _grace}) {
    controller = CallRecordingsLoadController(
      grace: grace,
      now: clock.now,
      scheduleTimer: clock.schedule,
    );
  }

  final _FakeClock clock = _FakeClock();
  late final CallRecordingsLoadController controller;
}
