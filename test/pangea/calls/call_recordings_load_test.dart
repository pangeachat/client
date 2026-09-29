import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_recordings_load.dart';

/// [CallRecordingsLoadController]'s loading machine (design spec section 3):
/// a pure resolver total over (reads in flight?) x (halves present?) x
/// (merge present?) x (grace elapsed?), plus a stateful shell that stamps a
/// grace baseline off a MONOTONIC elapsed reading and re-evaluates on every
/// fed input.
///
/// Every controller test drives a FAKE monotonic clock and a FAKE one-shot
/// timer scheduler (see [_FakeClock]/[_FakeTimer], mirroring
/// `call_audio_merge_coordinator_test.dart`'s own `_Scheduler`/`_FakeTimer`
/// simplified to one-shot only), so a grace window's own expiry is provable
/// without a real wait. [_FakeClock] additionally tracks a SEPARATE fake
/// wall clock, unconnected to the controller (which has no wall-clock input
/// at all -- see [CallRecordingsLoadController]'s own constructor), purely
/// so a test can prove that a wall-clock correction has no effect on grace
/// timing. Where the task names a specific mutation, the comment on the test
/// below names it and the assertion that catches it.

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
        elapsed: clock.elapsed,
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

    test('a wall-clock correction during the grace window has NO EFFECT on '
        'the monotonic grace timing -- unavailable arrives at exactly one '
        'grace, never extended', () {
      // Supersedes an earlier "round-8" test that pinned a WEAKER, only
      // partial fix: that version bounded each INDIVIDUAL re-arm to at
      // most a fresh `grace`, but the grace was still measured off the
      // WALL clock (`now()`), so a single large backward correction could
      // still balloon the OVERALL wait across several compounding re-arms.
      // Concretely, for a -60s correction against a 30s grace: the real
      // timer fires at real 30s, but the (wall-clock-computed) apparent
      // elapsed there still reads -30s (clamped to 0), so it re-arms a
      // FRESH 30s instead of resolving terminal; it fires again at real
      // 60s, apparent elapsed reads 0s, re-arming yet another fresh 30s;
      // only at real 90s does the apparent elapsed finally reach 30s and
      // resolve `unavailable` -- three times the promised grace, entirely
      // from one wall-clock correction.
      //
      // The actual fix: `_graceElapsed`/`_armTimer` now measure elapsed
      // time with the injected MONOTONIC `elapsed` seam (see the
      // constructor's own doc), never a wall clock -- so this controller
      // has no wall-clock input left to correct in the first place.
      // `adjustWallClock` below drives `_FakeClock`'s OWN separate wall
      // clock (see its class doc), entirely unconnected to the controller;
      // it is exercised here purely to prove that disconnection holds.
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);

      // A wall-clock correction (NTP step, manual clock change) moves the
      // system's wall clock BACKWARD by 60s -- larger than the grace
      // itself, and exactly the shape that made the overall wait balloon
      // under the superseded fix described above.
      h.clock.adjustWallClock(const Duration(seconds: -60));

      // Advancing MONOTONIC time to just under one grace still reads
      // pendingMerge ...
      h.clock.advance(_grace - _oneMs);
      expect(h.controller.state.value, CallRecordingsLoadState.pendingMerge);
      // ... and to exactly one grace flips straight to unavailable RIGHT
      // HERE -- not after a second or third additional grace the old
      // wall-clock-diff bug would have demanded.
      h.clock.advance(_oneMs);
      // Mutation (the bug this test replaces): change `_graceElapsed`/
      // `_armTimer` back to measuring elapsed time off a wall-clock
      // reading (e.g. reintroducing a `now: DateTime Function()` seam and
      // computing `now().difference(startedAt)`) instead of the injected
      // monotonic `elapsed()` -> the -60s correction above makes the
      // apparent elapsed read far less than the grace at this exact
      // monotonic instant, so the state is still `pendingMerge` here (it
      // would take a further ~60s of monotonic advance, via compounding
      // re-arms, to finally reach `unavailable`) -> RED. Verified by
      // temporarily reverting `_graceElapsed`/`_armTimer` to the prior
      // wall-clock-diff implementation and confirming this exact
      // assertion fails for this exact reason, then restoring the fix.
      expect(h.controller.state.value, CallRecordingsLoadState.unavailable);
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

      // The underlying notifier is genuinely disposed too here (the
      // IMMEDIATE, non-reentrant path -- `dispose()` called from OUTSIDE
      // any `_reevaluate` call, same as an ordinary widget's own
      // `State.dispose()`), not merely logically flagged: `addListener` on
      // an already-disposed `ValueNotifier` throws (confirmed against this
      // project's pinned Flutter SDK). `state` is `_stateNotifier` itself
      // (see its own doc), so this also proves `dispose()`'s immediate
      // branch actually calls `_stateNotifier.dispose()`, not just sets the
      // `_disposed` flag checked above.
      expect(
        () => h.controller.state.addListener(() {}),
        throwsA(isA<FlutterError>()),
      );
    });

    test('dispose() cancels a pending grace timer', () {
      final h = _Harness();
      h.controller.update(readsInFlight: false, halfCount: 1, hasMerge: false);
      expect(h.clock.scheduledCount, 1);

      h.controller.dispose();
      expect(h.clock.scheduledCount, 0);
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

      // The underlying notifier is genuinely disposed here too, via the
      // DEFERRED teardown path (`_reevaluate`'s own `finally`, which has
      // already run to completion by the time `update()` above returns,
      // since `dispose()` was called from INSIDE the very notification the
      // state change it reacts to just triggered -- see `dispose()`'s own
      // doc): `addListener` on an already-disposed `ValueNotifier` throws
      // (confirmed against this project's pinned Flutter SDK). This proves
      // the DEFERRED branch specifically -- not just the immediate one the
      // "no notify after dispose" test already covers -- actually calls
      // `_stateNotifier.dispose()`, not just sets the `_disposed` flag.
      expect(
        () => h.controller.state.addListener(() {}),
        throwsA(isA<FlutterError>()),
      );

      // An ordinary second dispose() call -- e.g. the owning widget's own
      // `State.dispose()`, unaware a listener already tore this down --
      // must remain a harmless no-op. This one genuinely can throw straight
      // out to the caller (nothing wraps it in a notify loop), so
      // `returnsNormally` is the right check here.
      expect(() => h.controller.dispose(), returnsNormally);
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
/// `Timer.new` on the same terms `call_audio_merge_coordinator_test.dart`'s
/// own `_Scheduler`/`_FakeTimer` stand in for [DateTime.now]/`Timer.new`
/// there -- simplified to one-shot only, since [CallRecordingsLoadController]
/// never schedules a periodic timer.
///
/// Tracks TWO separate timelines, not one: [_monotonic] is real elapsed
/// time, advanced ONLY by [advance], and is what every scheduled timer's own
/// due instant is measured against (mirroring how a real [Timer] is
/// scheduled against a monotonic clock internally, immune to a wall-clock
/// change happening around it) AND what [elapsed] reports -- the only clock
/// [CallRecordingsLoadController] itself is ever given (see its
/// constructor's own doc: it has no wall-clock input at all). [_wallClock]
/// is a SEPARATE, purely-fake system wall clock that [now] reports,
/// advanced by [advance] the same way an ordinary, uncorrected wall clock
/// would be, but ALSO independently adjustable by [adjustWallClock] without
/// moving [_monotonic] (or [elapsed]) at all. Nothing in
/// [CallRecordingsLoadController] reads [now] or [_wallClock] post-fix; both
/// are kept here purely so a test can simulate a wall-clock correction (NTP,
/// a manual clock change) and prove the controller's grace timing is
/// genuinely unaffected by it -- see the "wall-clock correction... has NO
/// EFFECT" test. An earlier version of this fake used a single [DateTime]
/// for both purposes, which could not express a wall-clock correction as
/// anything other than real time itself moving backward -- collapsing the
/// exact distinction that test relies on.
class _FakeClock {
  DateTime _wallClock = DateTime.utc(2026, 1, 1);
  Duration _monotonic = Duration.zero;
  final List<_Scheduled> _scheduled = [];

  DateTime now() => _wallClock;

  /// The monotonic elapsed-time seam [CallRecordingsLoadController] is
  /// actually constructed with in every test (see [_Harness]) -- immune to
  /// [adjustWallClock] by construction, exactly like a real [Stopwatch].
  Duration elapsed() => _monotonic;

  /// Counts only still-active (neither fired nor cancelled) timers -- a
  /// direct way for a test to prove "no timer is currently armed" without
  /// reaching into the controller's own private state.
  int get scheduledCount =>
      _scheduled.where((entry) => entry.timer.isActive).length;

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
  /// callback's own point in the sequence -- had not actually elapsed
  /// yet. Back when `CallRecordingsLoadController.retry` re-stamped its
  /// grace window from [now] (wall-clock diffs -- since replaced by the
  /// monotonic [elapsed] seam), that corruption produced a DIFFERENT,
  /// WRONG result depending purely on how a test happened to CHUNK its
  /// [advance] calls -- e.g. a single 60s [advance] spanning two
  /// grace-timer firings disagreeing with two separate 30s [advance]
  /// calls reaching the exact same due instants, with no clock correction
  /// involved at all. [_monotonic] (and so [elapsed]) was never the buggy
  /// half of that -- it is, and always was, stepped correctly here -- but
  /// [_wallClock] is still advanced the same careful way for its own sake,
  /// since [now] remains a general-purpose fake wall clock other tests (or
  /// a future consumer) may still read.
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
  /// BACKWARD), without moving real/[_monotonic] (or [elapsed]) time or
  /// firing or rescheduling anything -- simulating a wall-clock correction
  /// a real system clock can undergo (NTP, a manual change, a
  /// timezone/DST edge case) independent of how much real time has
  /// actually passed. [CallRecordingsLoadController] has no [now]-based
  /// input to be corrupted by this at all post-fix -- this exists purely
  /// so a test can prove exactly that.
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
      elapsed: clock.elapsed,
      scheduleTimer: clock.schedule,
    );
  }

  final _FakeClock clock = _FakeClock();
  late final CallRecordingsLoadController controller;
}
