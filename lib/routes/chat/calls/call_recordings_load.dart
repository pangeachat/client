import 'dart:async';

import 'package:flutter/foundation.dart';

/// How long [CallRecordingsLoadController] waits, once both recording reads
/// have landed with at least one half present but no merged row yet, before
/// giving up and reporting [CallRecordingsLoadState.unavailable]. See
/// `docs/handoff/2026-09-10-recordings-ui-redesign-spec.md` section 3 (D1):
/// "expected-participant HINT + a bounded ~30s grace TIMER ... error only
/// after the timer."
const kCallMergeGrace = Duration(seconds: 30);

/// The "Full call" slot's own loading state (design spec section 3), replacing
/// the `data ?? const []` handling that made "still loading" indistinguishable
/// from "nothing recorded".
///
/// Exhaustive over (reads in flight?) x (halves present?) x (merge present?)
/// x (grace elapsed?) -- see [resolveCallRecordingsLoadState] for the
/// resolution table and [CallRecordingsLoadController] for the stateful
/// machine that drives it off real inputs and a real clock.
enum CallRecordingsLoadState {
  /// Either the recordings read or the merged-row read is still in flight.
  loading,

  /// A merged row is present. The terminal, happy-path state -- once
  /// reached, [CallRecordingsLoadController] never moves away from it again,
  /// even on later input that would otherwise resolve to something else (see
  /// the controller's re-evaluation contract).
  ready,

  /// Reads are done, at least one per-device half is present, there is no
  /// merged row yet, and the grace window has not elapsed. A late merge
  /// moves this to [ready]; elapsed grace time -- never participant
  /// membership -- moves it to [unavailable] (ordinarily via the armed timer
  /// firing with no further input, but a plain
  /// [CallRecordingsLoadController.update] that happens to land after the
  /// grace has already run out resolves there directly too; either way,
  /// membership alone never does). [CallRecordingsLoadController.retry],
  /// the other direction, resets the grace stamp to the instant it is
  /// called, so the resolution it immediately triggers sees only the
  /// negligible real time the reset and the check are apart -- not
  /// however much had already run out -- for any sensibly-configured
  /// (POSITIVE, non-vanishing) [CallRecordingsLoadController.grace]; see
  /// that constructor's own doc for why [grace] is constrained at all.
  pendingMerge,

  /// Reads are done, there are zero halves at all, and (implied by
  /// [resolveCallRecordingsLoadState]'s own precedence, which checks a
  /// merge first) no merged row either. Nothing is currently known to be
  /// coming, so this is reported IMMEDIATELY rather than waiting out the
  /// grace on a guess -- not a promise that a half can never arrive later
  /// (one still can; see [CallRecordingsLoadController._graceStartedAt]'s
  /// own doc for how a late one is handled without granting it a fresh
  /// grace window).
  none,

  /// Reads are done, at least one half is present, there is no merged row,
  /// and the grace window has elapsed. Unlike [ready], this is NOT latched:
  /// a late merge moves it to [ready] (spec section 3's one accepted flash),
  /// [CallRecordingsLoadController.retry] moves it back to [pendingMerge],
  /// and a caller reporting reads in flight again moves it to [loading] --
  /// the same ordinary [resolveCallRecordingsLoadState] re-evaluation any
  /// other non-terminal state gets. What does NOT move it is more of the
  /// same non-answer: another half arriving with still no merge leaves the
  /// grace already elapsed, so it resolves right back here.
  unavailable,
}

/// The pure resolution table behind the "Full call" loading machine (design
/// spec section 3). Total over its four inputs: every combination maps to
/// exactly one state, so a caller never needs a fallback branch.
///
/// | readsInFlight | hasMerge | halfCount | graceElapsed | -> state         |
/// |---------------|----------|-----------|--------------|------------------|
/// | true          | any      | any       | any          | loading          |
/// | false         | true     | any       | any          | ready            |
/// | false         | false    | 0         | any          | none (immediate) |
/// | false         | false    | >=1       | true         | unavailable      |
/// | false         | false    | >=1       | false        | pendingMerge     |
///
/// The IF-chain order below is the precedence, not an arbitrary choice:
/// [readsInFlight] wins over everything (a stale `halfCount`/`hasMerge` left
/// from a previous call must never show while a fresh read is still
/// running); [hasMerge] wins over `halfCount`/grace (a late merge always
/// resolves to [CallRecordingsLoadState.ready], including from
/// [CallRecordingsLoadState.unavailable] -- the one accepted flash spec
/// section 3 calls for); zero halves is reported the instant reads finish,
/// NEVER waiting out the grace (spec section 3's NONE bullet, g2's "the case
/// that fell through" the original `data ?? const []` handling); only what
/// remains -- at least one half, no merge -- ever consults the grace timer
/// at all.
CallRecordingsLoadState resolveCallRecordingsLoadState({
  required bool readsInFlight,
  required int halfCount,
  required bool hasMerge,
  required bool graceElapsed,
}) {
  if (readsInFlight) return CallRecordingsLoadState.loading;
  if (hasMerge) return CallRecordingsLoadState.ready;
  if (halfCount == 0) return CallRecordingsLoadState.none;
  if (graceElapsed) return CallRecordingsLoadState.unavailable;
  return CallRecordingsLoadState.pendingMerge;
}

/// Owns the "Full call" slot's loading state across the recordings/merged
/// reads and the grace timer (design spec section 3), with a fully injected
/// clock and timer scheduler so a test drives every transition -- including a
/// timer's own expiry -- without a real wait. Mirrors
/// `CallAudioMergeCoordinator`'s own `clock`/`oneShotTimer` injection
/// (`call_audio_merge_coordinator.dart`) rather than inventing a new shape for
/// the same problem.
///
/// Deliberately excludes participants from the machine itself: the spec's
/// expected-participant HINT only ever informs a per-half "Waiting for
/// {name}'s recording…" label on the per-device rows (layout item 4/5, a
/// different agent's file) -- it is never an input [resolveCallRecordingsLoadState]
/// sees, and never what ends [CallRecordingsLoadState.pendingMerge]. Elapsed
/// grace time alone does (see that state's own doc for the two ordinary ways
/// it happens), so a room whose second participant is simply unknown
/// behaves identically to one where it is known: neither ever blocks or
/// shortens the same fixed grace.
///
/// The caller drives this with exactly one feed, [update], called whenever
/// the recordings/merged reads or the room's late events change (the widget
/// layer's `FutureBuilder`s and any subsequent rebuild); this class works out
/// everything else -- when reads complete, when the grace timer should be
/// armed, and when it should fire -- from that one feed. [retry] is the only
/// other write: it restarts the grace window so a re-run fetch gets a fresh
/// chance, without itself knowing anything about the fetch (the caller reruns
/// it and reports the outcome back through [update], same as any other
/// update).
///
/// Reentrancy: a listener on [state] IS allowed to call [update], [retry],
/// or [dispose] synchronously, from inside the very notification that
/// change just triggered -- see [_reevaluate] and [dispose]'s own docs for
/// how each of those is handled correctly and without leaking a [Timer].
/// What is NOT handled, on the same terms Flutter's own [ChangeNotifier]/
/// [ValueNotifier] never handle it either: a listener that feeds a
/// transformation of [state]'s own just-published value BACK into [update]
/// UNCONDITIONALLY, so that every publish keeps triggering a further
/// publish, never converging. That is a divergent listener, not a bounded
/// reentrant one, and no amount of internal bookkeeping here can make an
/// unbounded synchronous call chain safe -- the same is true of a listener
/// on any plain [ValueNotifier] that writes back to it on every change. A
/// real caller of this class only ever feeds independently-sourced facts
/// (a recordings/merged read, a room sync event), never a function of this
/// controller's own current [state], so this is not expected to be reached
/// in practice; it is named here because an adversarial review raised it,
/// and it is a genuine, if inherent, property worth a caller knowing about
/// rather than a silently-assumed one.
///
/// Deliberately does NOT extend [ChangeNotifier], unlike this feature's
/// sibling controllers: it has no use for the inherited `notifyListeners`/
/// `addListener`/`removeListener` on `this` -- [state] is the one and only
/// notification channel this class offers -- and, an adversarial review of
/// an earlier version of this file found, extending [ChangeNotifier] for
/// "structural" reasons alone is not free. `@protected` on
/// `ChangeNotifier.notifyListeners` is an ANALYZER hint, not a language
/// access restriction: an external caller can still write
/// `controller.addListener(controller.dispose); controller.notifyListeners();`
/// and have it compile and run, reaching [dispose] from inside `this`'s own
/// notification and hitting the exact `_notificationCallStackDepth == 0`
/// hazard the rest of this class works hard to keep [_stateNotifier] safe
/// from -- for `this` instead, which a `final` class modifier (closing only
/// the SUBCLASSING route to an inherited method, not a call to one directly
/// on an existing instance) does nothing to prevent. Not inheriting
/// [ChangeNotifier] at all closes the whole class of hazard structurally:
/// there is no `notifyListeners`/`addListener` on `this` for any caller,
/// well-behaved or not, to reach.
///
/// Declared `final` anyway (no subclassing, implementing, or mixing-in
/// outside this library): a state machine this self-contained has no
/// legitimate reason to be extended, and keeping that door shut costs
/// nothing.
final class CallRecordingsLoadController {
  /// [now] and [scheduleTimer] default to the real [DateTime.now] and a real
  /// [Timer], respectively; a test injects fakes instead (see
  /// call_recordings_load_test.dart's `_FakeClock`) so a grace window's own
  /// expiry is provable without a real wait. BOTH carry the same contract a
  /// real [DateTime.now]/[Timer] naturally satisfy but an injected
  /// replacement must be written to honour: neither may synchronously call
  /// back into this controller before returning. For [scheduleTimer]
  /// specifically: one that calls, say, [update] or [dispose] before
  /// returning its [Timer] handle could see that handle assigned to
  /// [_timer] AFTER such a call already ran [_cancelTimer] against whatever
  /// was there before, leaking the handle this very call is about to
  /// produce. [now] carries the identical risk from a different call site:
  /// [_armTimer] calls [now] AFTER the disposed check in [_reevaluate] has
  /// already passed, so a [now] that disposes this controller as a side
  /// effect on that specific call would still let [_armTimer] finish
  /// arming a timer for an already-disposed machine, because nothing
  /// downstream of that one check re-verifies it. This is a contract on
  /// both injected seams, not a runtime-enforced one on either: a fake
  /// clock or scheduler that violates it is a test-double bug to fix in
  /// the double, the same way a fake clock whose [now] moves BACKWARDS
  /// between calls would be -- this class trusts both the same way it
  /// trusts [resolveCallRecordingsLoadState] to be pure. Found by an
  /// adversarial review of this exact file, which first raised it for
  /// [scheduleTimer] and then, in a later round, for [now] too.
  ///
  /// [grace] must be POSITIVE. A [Duration.zero] (or a call-to-call gap on
  /// the underlying clock even a positive but vanishingly small one could
  /// lose to) would make [_graceElapsed] read true on the very first check
  /// after a fresh stamp -- including the one [retry] itself triggers --
  /// which would defeat the entire point of a grace window.
  CallRecordingsLoadController({
    this.grace = kCallMergeGrace,
    DateTime Function()? now,
    Timer Function(Duration duration, void Function() callback)? scheduleTimer,
  }) : assert(grace > Duration.zero, 'grace must be positive'),
       _now = now ?? DateTime.now,
       _scheduleTimer = scheduleTimer ?? _realTimer;

  /// How long [CallRecordingsLoadState.pendingMerge] is held before this
  /// machine gives up and reports [CallRecordingsLoadState.unavailable].
  final Duration grace;

  final DateTime Function() _now;
  final Timer Function(Duration duration, void Function() callback)
  _scheduleTimer;

  /// The single source of truth for [state]'s published value. Never
  /// exposed directly (see [state]'s own doc) -- but one residual way to
  /// observe a live reference to THIS object is inherent to using
  /// [ValueNotifier]/[ChangeNotifier] at all, not something this class
  /// itself can fix: in a DEBUG-mode run (never release or profile --
  /// confirmed against this project's pinned Flutter SDK,
  /// `foundation/memory_allocations.dart`: the dispatch that would do this
  /// is wrapped in an `assert(() {...}())`, which compiles away entirely
  /// outside debug mode) with a listener ALREADY registered on Flutter's
  /// own `FlutterMemoryAllocations.instance` singleton before this object
  /// is constructed, [ValueNotifier]'s own constructor publishes an
  /// `ObjectCreated` event carrying this exact instance as `event.object`
  /// -- no exception path, no debugger, and no private-field access needed.
  /// This is universal to EVERY [ValueNotifier]/[ChangeNotifier]
  /// constructed anywhere in this app while such a listener is attached --
  /// which is precisely what Flutter DevTools' own memory/object-creation
  /// tracking, an explicit opt-in developer tool, does -- not a property of
  /// this class's own design, and not avoidable without abandoning
  /// [ValueNotifier] here altogether, which would put this class out of
  /// step with every other controller in this codebase for an exposure
  /// that only ever exists in a debug or test run with that specific
  /// tooling attached, never in a shipped release build. Disclosed here
  /// rather than silently assumed away: an adversarial review of this exact
  /// file raised it as a fourth path back to this object, after the three
  /// genuinely closed above -- [state]'s own guard against a direct
  /// downcast, this class no longer extending [ChangeNotifier] itself (see
  /// the class doc), and [_ReadOnlyValueListenable.addListener]'s own guard
  /// against the `informationCollector` leak.
  final ValueNotifier<CallRecordingsLoadState> _stateNotifier = ValueNotifier(
    CallRecordingsLoadState.loading,
  );

  /// The concrete wrapper [state] exposes, held here under its own private,
  /// concrete type (rather than only as [state]'s public [ValueListenable]
  /// type) so [dispose] can reach [_ReadOnlyValueListenable._releaseListeners]
  /// on it directly -- see that method's own doc for why disposal needs it.
  late final _ReadOnlyValueListenable<CallRecordingsLoadState> _stateWrapper =
      _ReadOnlyValueListenable(_stateNotifier);

  /// A read-only view onto [_stateNotifier], wrapping rather than exposing
  /// it directly. Returning [_stateNotifier] itself, merely typed as
  /// [ValueListenable], does NOT actually stop an external caller from
  /// downcasting it back to the concrete [ValueNotifier] and writing
  /// `.value` directly -- Dart's static typing does not hide the runtime
  /// type. A caller that did so (however unlikely) would trigger
  /// [_stateNotifier]'s own `notifyListeners()` with [_evaluating] still
  /// false, since that write never goes through [_reevaluate] at all; a
  /// listener reacting by calling [dispose] would then hit the exact
  /// `_notificationCallStackDepth == 0` assertion the whole
  /// [_teardownDeferred] mechanism exists to prevent, completely unprotected
  /// -- not extending [ChangeNotifier] (see the class doc) closes that
  /// hazard for `this`, but [_stateNotifier] is a REAL [ValueNotifier] this
  /// class owns and must still guard on its own terms; this wrapper is that
  /// guard. Found by an adversarial review of this exact file.
  ValueListenable<CallRecordingsLoadState> get state => _stateWrapper;

  /// The number of listener registrations [state] is still holding
  /// (counting a [state]-added listener registered twice as two -- see
  /// [_ReadOnlyValueListenable._wrapped]'s own doc), exposed only so a test
  /// can prove [dispose] releases every one of them -- see [dispose]'s own
  /// doc, and [_ReadOnlyValueListenable._releaseListeners]'s. Not
  /// meaningful outside a test: production code has no legitimate reason to
  /// introspect its own listener count.
  @visibleForTesting
  int get debugListenerCount => _stateWrapper._listenerCount;

  /// Assumed true until the first [update] call says otherwise, so a caller
  /// whose very first feed already reports `readsInFlight: false` still gets
  /// a correctly-stamped [_graceStartedAt] from that first call, on exactly
  /// the same terms a later true->false transition would.
  bool _readsInFlight = true;
  int _halfCount = 0;
  bool _hasMerge = false;

  /// Stamped the instant [_readsInFlight] is observed to transition from true
  /// to false (spec section 3: "stamped the instant BOTH reads first
  /// complete"), and re-stamped to "now" by [retry]. This is stamped
  /// UNCONDITIONALLY on that edge -- regardless of what `halfCount`/`hasMerge`
  /// happen to be at that moment -- so a half that trickles in only after an
  /// initial zero-halves report still counts down from when reads first
  /// completed, never from when the half itself arrived.
  ///
  /// Null only before reads have ever been observed complete; [_graceElapsed]
  /// treats that as "not started" (false), which is safe because the only
  /// states that ever consult it ([CallRecordingsLoadState.pendingMerge] /
  /// [CallRecordingsLoadState.unavailable]) themselves require
  /// `readsInFlight == false`, and this field is always stamped in the SAME
  /// synchronous step that first flips [_readsInFlight] false.
  DateTime? _graceStartedAt;

  Timer? _timer;
  bool _disposed = false;

  /// True for the ENTIRE duration of one top-level [_reevaluate] call --
  /// from before it publishes anything to after it has synced [_timer] to
  /// the result. Lets [_reevaluate] tell a genuinely NEW (top-level) call
  /// apart from a REENTRANT one arriving while a top-level call is still
  /// unwinding; see [_reevaluate]'s own doc for why that distinction exists,
  /// and why it spans publishing too, not merely the timer step.
  bool _evaluating = false;

  /// Set by [dispose] when it is called while [_evaluating] is true -- see
  /// that method's own doc for why the actual [_stateNotifier] teardown
  /// must wait for the top-level [_reevaluate] call to finish unwinding.
  bool _teardownDeferred = false;

  /// Feeds live inputs in. Called by the widget layer whenever the
  /// recordings/merged reads or the room's late events change -- including
  /// every recomputation the `FutureBuilder`s already trigger today, and any
  /// later sync event that adds a half or a merge.
  ///
  /// The [_disposed] check below is an EFFICIENCY guard, not a load-bearing
  /// correctness one: [_reevaluate]'s own check (see its doc) already stops
  /// the timer from ever being touched once disposed, for every call shape
  /// -- one made long after a plain [dispose], or one reentrant during the
  /// very call that disposes this controller -- because that check runs
  /// AFTER [_publishOnce] has fully returned, by which point any such
  /// disposal has already happened. This check exists so a call already
  /// known to be pointless skips mutating any field or resolving anything
  /// at all, rather than doing that work only to discover the same thing a
  /// few lines later.
  void update({
    required bool readsInFlight,
    required int halfCount,
    required bool hasMerge,
  }) {
    if (_disposed) return;

    final wasInFlight = _readsInFlight;
    _readsInFlight = readsInFlight;
    _halfCount = halfCount;
    _hasMerge = hasMerge;

    // The ONE moment `_graceStartedAt` is stamped from live data: reads were
    // in flight and have just finished. A later `update` reporting more
    // halves, or reads back in flight again, never re-stamps it -- only this
    // exact edge does; see the field's own doc for why that is deliberate.
    if (wasInFlight && !readsInFlight) {
      _graceStartedAt = _now();
    }

    _reevaluate();
  }

  /// Resets the grace window to a fresh full [grace] and re-evaluates,
  /// returning [CallRecordingsLoadState.unavailable] to
  /// [CallRecordingsLoadState.pendingMerge] (assuming the last known
  /// `halfCount`/`hasMerge` still call for it) exactly as if reads had just
  /// finished again.
  ///
  /// Deliberately does NOT itself touch `readsInFlight`, `halfCount`, or
  /// `hasMerge`: the caller re-runs the actual fetch and reports its outcome
  /// through [update] as normal, which is what actually carries this to
  /// [CallRecordingsLoadState.loading] and then to whatever the fresh read
  /// resolves to. Calling this while already
  /// [CallRecordingsLoadState.ready] is a harmless no-op: [_publishOnce]'s
  /// latch on that terminal state ignores the fresh stamp along with
  /// everything else.
  void retry() {
    if (_disposed) return;
    _graceStartedAt = _now();
    _reevaluate();
  }

  /// Publishes the current state immediately, then -- ONLY for the
  /// outermost, non-reentrant call -- syncs [_timer] to whatever ends up
  /// published. Called after every [update] and every [retry]. This is a
  /// genuinely TWO-PHASE evaluation, not one -- read both halves below
  /// before changing either.
  ///
  /// PHASE 1, [_publishOnce]: runs EVERY time this method is called, even
  /// reentrantly, with no coalescing at all. This is deliberate and is not
  /// merely "safe to skip coalescing" -- it is REQUIRED for correctness. A
  /// listener on [state] reacting to a publish may call [update] or [retry]
  /// synchronously, and that reentrant call may report something genuinely
  /// different (a merge that just arrived). If publishing were deferred the
  /// way the timer step below is, a MOMENTARY value fed by one reentrant
  /// call could be silently overwritten by a second, later reentrant call
  /// in the same synchronous burst before any pass ever evaluated it --
  /// e.g. `update(hasMerge: true)` immediately followed, in the same
  /// listener callback, by `update(hasMerge: false)`, which must still
  /// latch [CallRecordingsLoadState.ready] rather than silently losing the
  /// merge. Running [_publishOnce] immediately and unconditionally is what
  /// gives that momentary value its own genuine chance to be evaluated --
  /// and, if it is a merge, LATCHED -- the instant it is fed, before a
  /// later, contradictory call can overwrite the fields out from under it.
  /// [_publishOnce] is safe to call this way because it is idempotent:
  /// [_setState]'s own same-value check makes a redundant publish a no-op,
  /// and its ready latch makes an already-published
  /// [CallRecordingsLoadState.ready] impossible to unpublish. An
  /// adversarial review of an earlier version of this file found the loss
  /// this fixes, reproduced in call_recordings_load_test.dart's "still
  /// latches ready even when a later reentrant update" test.
  ///
  /// A reentrant [dispose] (see that method's own doc) can flip [_disposed]
  /// true from inside the notification [_publishOnce] just triggered --
  /// checked immediately after, before phase 2 ever touches the timer.
  ///
  /// PHASE 2, [_syncTimerFor]: only the OUTERMOST call -- the one that flips
  /// [_evaluating] from false to true -- ever calls it, and does so exactly
  /// ONCE, reading `_stateNotifier.value` AFTER its own [_publishOnce] call
  /// has fully returned. Because every reentrant call's own [_publishOnce]
  /// runs and completes SYNCHRONOUSLY, nested entirely inside that outer
  /// [_publishOnce] call, by the time the outer call reads
  /// `_stateNotifier.value` it is reading whatever the ENTIRE synchronous
  /// burst finally settled on. [_syncTimerFor] itself always calls
  /// [_cancelTimer] before conditionally re-arming, so calling it a SECOND
  /// time for the SAME live value -- purely with respect to two arms
  /// racing to own [_timer] -- would be harmless, not a leak. That is NOT
  /// the whole safety story, though: [_syncTimerFor] carries no [_disposed]
  /// check of its own (see its own doc) precisely BECAUSE it has exactly
  /// one call site, immediately after the outer branch's own
  /// `if (_disposed) return;`. A reentrant [dispose] (the paragraph above)
  /// can be triggered from arbitrarily deep inside the reentrant chain --
  /// e.g. a `none` notification whose reentrant `update()` moves things to
  /// `pendingMerge`, itself notifying a THIRD listener that disposes -- and
  /// if the REENTRANT branch also called [_syncTimerFor] at that point
  /// (even against the correct, live value) it would arm a timer for an
  /// ALREADY-disposed controller, because [_syncTimerFor] has no guard of
  /// its own to catch that. Skipping the timer step in the reentrant branch
  /// is therefore not merely an optimisation against redundant work, as an
  /// earlier version of this explanation put it -- it is also what lets
  /// [_syncTimerFor] safely go without a disposed check of its own at all,
  /// by keeping it to the ONE call site that already has one immediately
  /// before it.
  ///
  /// The one thing that IS unsafe, and the actual bug an earlier version of
  /// this method had: reading a value CAPTURED before the reentrant chain
  /// ran, rather than [_stateNotifier]'s own live value afterward. A
  /// captured local stays whatever it was resolved to at the moment it was
  /// computed -- stale the instant a nested reentrant call publishes
  /// something different -- so syncing the timer against it arms (or fails
  /// to arm) for a state nothing is in anymore. This is why [_syncTimerFor]
  /// takes the live `_stateNotifier.value` read at its own call site, never
  /// a value threaded through from earlier in the same call. Found by an
  /// adversarial review of this exact file, reproduced in
  /// call_recordings_load_test.dart's "still latches ready even when a
  /// later reentrant update" test's own sibling covering this specific
  /// staleness (see that test file's "listener that feeds a merge" test).
  ///
  /// (An earlier version of this method additionally coalesced the timer
  /// step with a `_dirty`-driven loop, mirroring
  /// `CallAudioMergeCoordinator`'s own "drain-until-clean" pattern
  /// (`call_audio_merge_coordinator.dart`); that loop was provably always
  /// exactly one iteration here, because -- unlike that coordinator's own
  /// per-pass work -- neither [_syncTimerFor] nor [_armTimer] calls any
  /// LISTENER or other observer of THIS controller (they touch only
  /// [_timer] and the injected [_scheduleTimer]/[_cancelTimer] seam, on the
  /// documented contract that a well-behaved scheduler returns its handle
  /// without first calling back into this controller -- see the
  /// constructor's own doc), so nothing during the loop's own body could
  /// ever re-dirty it. It was removed as dead complexity once that was
  /// understood, in favour of this direct read.) Both the loss PHASE 1
  /// fixes and the staleness bug above were found by adversarial review of
  /// this exact file; see call_recordings_load_test.dart's "listener
  /// reentrancy" tests for both.
  void _reevaluate() {
    if (_evaluating) {
      _publishOnce();
      return;
    }

    _evaluating = true;
    try {
      _publishOnce();
      if (_disposed) return;
      _syncTimerFor(_stateNotifier.value);
    } finally {
      _evaluating = false;
      if (_teardownDeferred) {
        _teardownDeferred = false;
        _stateNotifier.dispose();
        _stateWrapper._releaseListeners();
      }
    }
  }

  /// Resolves the current state from scratch via
  /// [resolveCallRecordingsLoadState] and publishes it. The whole machine's
  /// STATE (never its timer) is re-derived from (`_readsInFlight`,
  /// `_halfCount`, `_hasMerge`, `_graceStartedAt`, `_now()`) every time this
  /// runs, so there is exactly one place state is decided -- but see
  /// [_reevaluate]'s own doc for why this runs on EVERY call, including
  /// reentrant ones, unlike the timer-sync step.
  ///
  /// Never call this directly -- go through [_reevaluate].
  ///
  /// Deliberately returns nothing: the caller is expected to re-read
  /// [_stateNotifier]'s own value afterward (see [_reevaluate]'s outer
  /// branch) rather than being handed this call's own local `resolved`, so
  /// that a nested reentrant call's own, LATER publish -- which can happen
  /// synchronously inside [_setState] below -- is what the caller actually
  /// acts on. Returning (and the caller using) the stale local instead was
  /// tried and reproduces exactly the leak this file's reentrancy tests
  /// guard against; see call_recordings_load_test.dart's "listener that
  /// feeds a merge" test.
  void _publishOnce() {
    // READY is terminal (spec section 3: "the terminal state once the merge
    // lands"): once reached, no further `update`/`retry` may move the
    // machine away from it, even if later input would otherwise resolve to
    // something else (e.g. a caller re-feeding `hasMerge: false`). This is
    // the one piece [resolveCallRecordingsLoadState] itself cannot express,
    // because it is stateless by design -- latching is exactly the
    // difference between a pure per-call resolution and a machine with
    // history. [_setState] independently guards [_disposed] for the actual
    // write, so this needs no check of its own for that.
    if (_stateNotifier.value == CallRecordingsLoadState.ready) return;

    final resolved = resolveCallRecordingsLoadState(
      readsInFlight: _readsInFlight,
      halfCount: _halfCount,
      hasMerge: _hasMerge,
      graceElapsed: _graceElapsed(),
    );

    _setState(resolved);
  }

  /// Syncs [_timer] to [published]: cancels whatever is currently armed,
  /// then arms a fresh one for the grace's remainder if and only if
  /// [published] is [CallRecordingsLoadState.pendingMerge].
  ///
  /// Never call this directly -- go through [_reevaluate], which is what
  /// keeps this from ever being called more than once per top-level
  /// evaluation (see its own doc): two independent calls for what should be
  /// one evaluation, un-coalesced, is exactly the leak an adversarial
  /// review found here. This carries no [_disposed] check of its own,
  /// deliberately: [_reevaluate] has exactly one call site for this method,
  /// immediately after its own `if (_disposed) return;`, with nothing in
  /// between that could change it -- a check here would be unreachable by
  /// construction, not merely in the current call graph, so it is left out
  /// rather than kept as dead weight.
  void _syncTimerFor(CallRecordingsLoadState published) {
    _cancelTimer();
    if (published != CallRecordingsLoadState.pendingMerge) return;
    _armTimer();
  }

  bool _graceElapsed() {
    final startedAt = _graceStartedAt;
    if (startedAt == null) return false;
    return _now().difference(startedAt) >= grace;
  }

  /// Schedules a single re-evaluation for whenever [grace] actually runs
  /// out -- not a flat [grace] every time this is called, so a late half at,
  /// say, 20s into a 30s grace does not hand the wait another full 30s on
  /// top of what has already elapsed (spec: "a late half within grace stays
  /// pendingMerge", not "restarts pendingMerge").
  ///
  /// [_graceStartedAt] is guaranteed non-null here: the only way to reach
  /// [CallRecordingsLoadState.pendingMerge] is through
  /// [resolveCallRecordingsLoadState] with `readsInFlight == false`, and that
  /// is always stamped in the same synchronous step ([update] or [retry])
  /// that produces it. The `!` documents that invariant rather than masking a
  /// violation of it with a silent fallback -- if it is ever broken, this
  /// should fail loudly the first time [CallRecordingsLoadState.pendingMerge]
  /// is reached without a stamp, not quietly hand out a full fresh grace.
  ///
  /// [elapsed] itself is clamped to never read NEGATIVE before being
  /// subtracted from [grace] below. [_now] is the real wall clock by
  /// default (see the constructor's own doc), and a wall clock can jump
  /// BACKWARD independent of how much real time has actually passed -- an
  /// NTP step correction, a manual clock change, a timezone/DST edge case
  /// -- entirely without a misbehaving injected [_now] (a REAL [Timer],
  /// once armed, is scheduled against a MONOTONIC clock internally and
  /// keeps firing on real elapsed time regardless of what the wall clock
  /// does in the meantime; it is only THIS calculation, run again when
  /// that timer fires or a fresh [update]/[retry] lands, that reads the
  /// wall clock at all). Without the clamp, a wall clock that appears to
  /// have gone backward since [startedAt] makes `grace -
  /// elapsed` LARGER than [grace] itself -- e.g. a 60s backward correction
  /// during a 30s grace would re-arm for 60s, not the 30s the caller was
  /// promised, silently ballooning how long a genuinely-stuck call sits in
  /// [CallRecordingsLoadState.pendingMerge] with no feedback. Clamping
  /// [elapsed] to zero treats an apparent backward jump as "no time has
  /// passed YET" -- the safe, conservative reading -- rather than
  /// subtracting a negative and handing out more than a fresh [grace].
  ///
  /// This does NOT fully solve wall-clock adjustment in general: a FORWARD
  /// jump (the wall clock skips ahead) still makes [elapsed] read LARGER
  /// than the real time that has passed, which can move
  /// [CallRecordingsLoadState.pendingMerge] to
  /// [CallRecordingsLoadState.unavailable] earlier than a genuine [grace]
  /// would have -- a strictly less harmful failure (the caller sees an
  /// actionable [retry] rather than an indefinitely-extended wait) that
  /// this clamp does not attempt to correct. Fully closing BOTH directions
  /// would mean measuring elapsed time against a MONOTONIC clock rather
  /// than [_now]'s wall-clock reading -- a larger change to this class's
  /// injected-clock shape than this fix makes, and not undertaken here.
  /// Found by an adversarial review of this exact file.
  void _armTimer() {
    final startedAt = _graceStartedAt!;
    final elapsed = _now().difference(startedAt);
    final remaining = grace - (elapsed.isNegative ? Duration.zero : elapsed);
    _timer = _scheduleTimer(
      remaining.isNegative ? Duration.zero : remaining,
      _onGraceElapsed,
    );
  }

  void _onGraceElapsed() {
    _timer = null;
    if (_disposed) return;
    _reevaluate();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// The one place [_stateNotifier] is ever written. Guards [_disposed] on
  /// top of, not instead of, the entry checks in [update]/[retry]: both
  /// check [_disposed] before ever calling [_reevaluate], and nothing
  /// between that check and [_publishOnce] running (a handful of field
  /// writes, no callouts) can change it -- so in the current call graph this
  /// check is unreachable in a disposed run. It is kept anyway as the actual
  /// leaf that would otherwise mutate a disposed [ValueNotifier] (which
  /// throws in a test/debug run) if a future caller of [_publishOnce] were
  /// ever added without its own entry check -- the same layered role
  /// `CallPlaybackController._setActiveIndex` plays for its own notifiers.
  void _setState(CallRecordingsLoadState resolved) {
    if (_disposed) return;
    if (resolved == _stateNotifier.value) return;
    _stateNotifier.value = resolved;
  }

  /// Cancels any pending timer, disposes [_stateNotifier], and marks this
  /// controller unusable. Idempotent: a second call is a harmless no-op.
  ///
  /// A listener on [state] is allowed to call this synchronously, from
  /// inside the very notification that change just triggered -- but
  /// [_stateNotifier] cannot safely be disposed right there: Flutter's own
  /// `ChangeNotifier.dispose()` asserts `_notificationCallStackDepth == 0`,
  /// specifically to forbid tearing a notifier down while it is still
  /// iterating its own listener list (confirmed against this project's
  /// pinned Flutter SDK, `foundation/change_notifier.dart`). [_disposed] is
  /// set true IMMEDIATELY either way -- every guard in this class keys off
  /// it, so no further evaluation or timer work happens from this instant on
  /// regardless -- but [_stateNotifier]'s OWN teardown is deferred via
  /// [_teardownDeferred] until [_reevaluate]'s own top-level call finishes
  /// unwinding (see its `finally`), which is exactly the moment its
  /// notification has fully returned and disposing it is safe again. Called
  /// from OUTSIDE any [_reevaluate] call -- the ordinary case, a widget's
  /// own `State.dispose()` -- [_evaluating] is already false and
  /// [_stateNotifier] is disposed immediately too, with no deferral at all.
  ///
  /// This class does not extend [ChangeNotifier] (see the class doc) and so
  /// has no `super.dispose()` of its own to call -- only [_stateNotifier]'s
  /// disposal ever needed deferring in the first place; `this` was never at
  /// risk the same way.
  ///
  /// [_stateWrapper._releaseListeners] runs at the exact same instant as
  /// [_stateNotifier]'s own disposal, on BOTH branches below: [_stateNotifier]
  /// disposing already drops every reference IT holds, but [_stateWrapper]'s
  /// own `_wrapped` map is a SEPARATE reference this class holds to every
  /// caller-supplied listener (and, transitively, anything a listener
  /// closure captures) -- nothing else would release it, and leaving it
  /// until only THIS controller itself became unreachable, rather than
  /// clearing it the moment [_stateNotifier] itself is torn down, would keep
  /// it alive for however much longer that turns out to be. See that
  /// method's own doc.
  ///
  /// Found, and the crash reproduced against the real SDK assertion, by an
  /// adversarial review of this exact file; see
  /// call_recordings_load_test.dart's "listener that calls dispose()" test.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelTimer();
    if (_evaluating) {
      _teardownDeferred = true;
    } else {
      _stateNotifier.dispose();
      _stateWrapper._releaseListeners();
    }
  }

  static Timer _realTimer(Duration duration, void Function() callback) =>
      Timer(duration, callback);
}

/// Forwards [value]/[addListener]/[removeListener] to [_inner] without
/// exposing [_inner] itself, so a caller holding only this wrapper's static
/// type has no runtime object to downcast back to the concrete
/// [ValueNotifier] and write `.value` on directly -- see
/// [CallRecordingsLoadController.state]'s own doc for why that matters here
/// specifically. No `dispose`, no `value` setter: nothing on this type
/// itself can reach [_inner].
///
/// [addListener] does NOT forward [listener] directly, though -- see its own
/// doc for the second, more surprising way [_inner] can otherwise escape.
class _ReadOnlyValueListenable<T> implements ValueListenable<T> {
  _ReadOnlyValueListenable(this._inner);

  final ValueListenable<T> _inner;

  /// Maps each caller-supplied [listener] to every WRAPPING closure
  /// currently registered on [_inner] for it, oldest first, so
  /// [removeListener] can find and remove the right one.
  ///
  /// A LIST, not a single wrapper, because [ChangeNotifier.addListener]
  /// documents that adding the exact same [listener] reference more than
  /// once is valid and additive -- "an additional instance is added, and
  /// must be removed the same number of times it is added before it will
  /// stop being called" -- and this wrapper must honour that same
  /// multiplicity contract, not merely approximate it. An earlier version
  /// of this map tracked only the LATEST wrapper per [listener] key,
  /// documented at the time as an "accepted divergence" for how unusual
  /// registering one callback twice already is -- but an adversarial
  /// review of this exact file pointed out that framing does not make the
  /// underlying behaviour correct: adding [listener] twice and removing it
  /// twice left ONE wrapper permanently registered on [_inner] with no way
  /// for the caller to reach it again, so a listener the caller correctly,
  /// symmetrically removed kept firing anyway. Every registration is
  /// tracked here now, so an Nth [addListener] genuinely requires an Nth
  /// [removeListener] before [listener] stops firing, exactly matching
  /// [_inner]'s own contract.
  ///
  /// This map is itself released by [_releaseListeners] once [_inner] is
  /// disposed -- see that method's own doc for why disposing [_inner] alone
  /// does not already take care of it.
  final Map<VoidCallback, List<VoidCallback>> _wrapped = {};

  @override
  T get value => _inner.value;

  /// Registers a WRAPPING closure for [listener] on [_inner], rather than
  /// [listener] itself, so that a [listener] which THROWS is caught HERE --
  /// before it ever reaches [_inner]'s own `notifyListeners()` catch block.
  ///
  /// Flutter's [ChangeNotifier.notifyListeners] catches a throwing
  /// listener's exception and reports it via [FlutterError.reportError],
  /// but the [FlutterErrorDetails] it builds attaches the notifying object
  /// ITSELF -- [_inner], the very [ValueNotifier] this wrapper exists to
  /// hide -- to `informationCollector` (as a `DiagnosticsProperty<
  /// ChangeNotifier>`; confirmed against this project's pinned Flutter SDK,
  /// `foundation/change_notifier.dart`). A caller with a global
  /// `FlutterError.onError` handler that inspects `informationCollector()`
  /// could recover a live reference to [_inner] from it and bypass this
  /// wrapper entirely -- the SAME hazard a direct downcast of [state] would
  /// be, reached a second way. This is the third round an adversarial
  /// review of this file found a distinct path back to the raw notifier
  /// (after direct exposure, and this class's own former [ChangeNotifier]
  /// inheritance); catching every listener's exception before it ever
  /// reaches [_inner]'s own notification loop closes the general class,
  /// not just this one instance of it -- no listener registered THROUGH
  /// this wrapper can ever trigger [_inner]'s own catch block at all.
  ///
  /// The caught exception is not swallowed: it is re-reported through a
  /// SEPARATE `FlutterError.reportError` call whose own `informationCollector`
  /// never mentions [_inner].
  ///
  /// That reporting call is itself wrapped in one more try/catch, for a
  /// reason specific to `FlutterError.reportError` rather than general
  /// paranoia: `FlutterError.reportError` does not guard its own call to
  /// `FlutterError.onError` (confirmed against this project's pinned
  /// Flutter SDK, `foundation/assertions.dart`: `onError?.call(details);`,
  /// no try/catch of its own) -- and `onError` is GLOBAL, ambient state
  /// this class does not own and never chose to trust the way it trusts its
  /// own injected `now`/`scheduleTimer` seams. Any code anywhere in the
  /// isolate can replace `onError`, including with one that itself throws.
  /// Without this inner guard, a throwing `onError` would turn this very
  /// reporting call into an exception escaping the wrapping closure below
  /// -- reaching [_inner]'s OWN `notifyListeners()` catch block exactly as
  /// if this wrapper did not exist, undoing the protection this method
  /// exists to provide, and exposing [_inner] through THAT catch block's
  /// own `informationCollector` instead. The inner catch swallows rather
  /// than re-reports: re-reporting would just call the same
  /// already-proven-broken handler again, and there is no more-honest place
  /// left to route a broken global error handler's own failure. This is not
  /// a NEW, fourth path back to the raw notifier -- it is a gap in THIS
  /// path's own closure above, found in the same adversarial round as the
  /// genuinely separate fourth path noted on [_stateNotifier]'s own doc:
  /// without this inner guard, a broken `onError` would silently reopen the
  /// exact path the outer catch above exists to close.
  @override
  void addListener(VoidCallback listener) {
    void wrapped() {
      try {
        listener();
      } catch (exception, stack) {
        try {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: exception,
              stack: stack,
              library: 'call_recordings_load',
              context: ErrorDescription(
                'while notifying a CallRecordingsLoadController.state '
                'listener',
              ),
            ),
          );
        } catch (_) {
          // See this method's own doc: a broken `FlutterError.onError`
          // must not be allowed to turn this reporting attempt into an
          // exception escaping `wrapped` itself.
        }
      }
    }

    // `_inner.addListener` runs FIRST, deliberately: it is the call that
    // can fail (it throws if `_inner` is already disposed -- confirmed
    // against this project's pinned Flutter SDK,
    // `foundation/change_notifier.dart`'s own `addListener`, which asserts
    // not-disposed before touching its internal list). A real
    // [ValueNotifier]'s own `addListener` is atomic under that failure: it
    // throws before mutating anything. Recording into [_wrapped] FIRST
    // would make THIS wrapper's own `addListener` non-atomic by
    // comparison -- a caller who (mistakenly) registers after disposal
    // would still get the same throw, but would ALSO leave a stale entry
    // in [_wrapped] that nothing could ever clean up afterward (`dispose`
    // is already a no-op by that point). Ordering this call first restores
    // the same atomicity a real [ValueNotifier] already gives callers.
    // Found by an adversarial review of this exact file.
    _inner.addListener(wrapped);
    (_wrapped[listener] ??= []).add(wrapped);
  }

  /// Removes ONE registration of [listener] -- the OLDEST one still
  /// tracked, not the newest -- matching [ChangeNotifier]'s own
  /// multiplicity contract: a [listener] added N times keeps firing until
  /// it has been removed N times too (see [_wrapped]'s own doc). WHICH of
  /// the N functionally-identical wrapping closures gets removed is NOT
  /// merely a bookkeeping preference -- it is observable when [listener]
  /// removes itself reentrantly from inside its own first firing within a
  /// single notification pass. [ChangeNotifier.removeListener] scans its
  /// internal list from index 0 and removes (or, mid-notification, nulls)
  /// the FIRST matching slot it finds; during an active notification, that
  /// slot is the one whose call has ALREADY been dispatched, so a
  /// not-yet-reached LATER slot holding the same raw listener is
  /// unaffected and still fires -- meaning a [listener] registered twice
  /// and removed once, from inside its own first call, fires TWICE in
  /// that SAME pass (confirmed against this project's pinned Flutter SDK).
  /// Removing the NEWEST wrapper here instead (an earlier version of this
  /// method did, via `List.removeLast`) would remove the NOT-YET-fired
  /// registration instead, silencing [listener] after only ONE call in
  /// that pass -- a real behavioural divergence from [ChangeNotifier],
  /// not merely a cosmetic one. Removing the OLDEST (`List.removeAt(0)`)
  /// reproduces the exact same observable outcome instead. Found by an
  /// adversarial review of this exact file.
  @override
  void removeListener(VoidCallback listener) {
    final wrappers = _wrapped[listener];
    if (wrappers == null || wrappers.isEmpty) return;
    final wrapped = wrappers.removeAt(0);
    _inner.removeListener(wrapped);
    if (wrappers.isEmpty) _wrapped.remove(listener);
  }

  /// Drops every listener this wrapper is tracking, called once [_inner]
  /// itself has been disposed (see
  /// [CallRecordingsLoadController.dispose]'s own doc for both call sites).
  /// [_inner]'s own disposal already clears every reference IT holds --
  /// but [_wrapped] is a SEPARATE reference this wrapper itself holds to
  /// every caller-supplied [VoidCallback] (as a map key, and again,
  /// captured inside each of its paired wrapping closures, as a map
  /// value). Nothing else releases that reference -- and anything a
  /// caller's listener closure captures along with it -- for as long as
  /// this wrapper, reachable through the owning
  /// [CallRecordingsLoadController]'s [CallRecordingsLoadController.state],
  /// itself stays reachable. Found by an adversarial review of this exact
  /// file.
  void _releaseListeners() => _wrapped.clear();

  /// The total number of live registrations this wrapper is tracking --
  /// summed across every [listener] key, not the number of distinct keys,
  /// so a [listener] registered twice (see [_wrapped]'s own doc) counts as
  /// two. Exposed only for
  /// [CallRecordingsLoadController.debugListenerCount].
  int get _listenerCount =>
      _wrapped.values.fold(0, (sum, wrappers) => sum + wrappers.length);
}
