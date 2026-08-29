import 'dart:math';

import 'package:matrix/matrix.dart';

/// The MSC4140 delayed-leave timings this app asks the SDK for.
///
/// A call membership stays alive because the client repeatedly restarts a
/// server-side delayed leave. The SDK ships 18s/4s and, left alone, that is one
/// write to Synapse every four seconds PER PARTICIPANT — 50 req/s across two
/// hundred people in calls, growing linearly, with every device on the same
/// period so a cohort that joined together stays phase-locked for the whole
/// call.
///
/// The numbers here are derived, not preferred. Three things bound them, and
/// the invariants are asserted in call_timeouts_test.dart rather than only
/// described:
///
/// 1. **The homeserver's own deadline.** A restart that lands later than
///    [applyLeave] after the previous one is too late: Synapse applies the
///    leave and the peer sees the caller vanish mid-call. So at least two
///    restart attempts must fit inside `applyLeave - requestBudget`, which
///    means `2 * maxRestart + requestBudget <= applyLeave` — one restart lost
///    to a bad moment on the network must never cost the membership.
///
/// 2. **`ActiveCall.endedDeliberatelyWithin`.** That constant separates "they
///    pressed end" from "their device died", and it was itself derived from
///    these two numbers: the earliest a SERVER-written retraction can appear is
///    `applyLeave - restart` after a device stops heartbeating, and anything
///    sooner than that cannot be the server's. Raising the restart interval
///    alone moves that retraction EARLIER, which is what would let a crash be
///    reported as a deliberate hangup. The two constants have to move together,
///    and `endedDeliberatelyWithin < applyLeave - maxRestart` is what says so.
///
///    **That relation is necessary, not sufficient, and the gap is not this
///    change's.** `ActiveCall` measures the window from when THIS CLIENT saw
///    the peer leave, which is the SFU's report — and the SFU keeps a departed
///    participant for its own retention window (`ActiveCall.peerGraceWindow`
///    is matched to it). When that retention is longer than
///    `applyLeave - restart`, the server's cleanup arrives first and a crash is
///    read as a hangup no matter what these two numbers are. It is true of the
///    SDK's 18s/4s as well; closing it would need
///    `applyLeave - maxRestart > SFU retention + endedDeliberatelyWithin`,
///    which is a much longer apply-leave and a decision of its own. What these
///    numbers guarantee is only the direction: the earliest retraction is never
///    moved EARLIER than the SDK would have put it.
///
/// 3. **Cost.** Everything above is satisfied by leaving 18s/4s alone. The
///    reason not to is the load, which is the whole point of the change.
///
/// What the longer [applyLeave] costs: a device that DIES rather than hanging
/// up leaves its membership in room state for up to thirty seconds instead of
/// eighteen. Nothing reads that as busy — `CallService.isBusy` is local session
/// state — so the visible effect is that a dead call's Return offer can stand
/// twelve seconds longer, which is a trade this feature had already accepted.
class CallDelayedLeave {
  CallDelayedLeave._();

  /// How long after the last restart the homeserver applies the leave.
  static const applyLeave = Duration(seconds: 30);

  /// The narrowest and widest restart interval a device may draw.
  ///
  /// A RANGE rather than a value, because identical periods are what turn
  /// linear load into a spike: a class that all joins at the top of the hour
  /// starts every timer within a second of every other, and `Timer.periodic`
  /// keeps them there for the length of the call. Each device draws once and
  /// keeps its draw, which de-phases the cohort within a couple of periods.
  ///
  /// Nine to eleven rather than eight to ten, and the reason is the tick count:
  /// only restarts landing before `applyLeave - requestBudget` (25s) are of any
  /// use, so a device tolerates an outage of `floor(25/T) * T`. Across [8s,10s]
  /// that count drops from three to two at 8.33s, and the worst case in the
  /// range is 16.7s. Across [9s,11s] it is two throughout and the worst case is
  /// 18s — a wider spread, a better floor, and a lower mean rate.
  static const minRestart = Duration(seconds: 9);
  static const maxRestart = Duration(seconds: 11);

  /// How long one restart request is allowed to take before it counts as late.
  ///
  /// Not a timeout anything enforces — the SDK's restart has no deadline of its
  /// own. It is the headroom the interval is chosen with: the budget a single
  /// `manageDelayedEvent` POST may burn on a bad mobile link without the next
  /// restart already being too late.
  static const requestBudget = Duration(seconds: 5);
}

/// The SDK timeouts this app runs calls with, with [CallDelayedLeave]'s restart
/// interval drawn for THIS device.
///
/// Only the two delayed-leave fields are overridden; every other SDK default is
/// inherited deliberately, so a change upstream still reaches us.
///
/// [random] is injected because the draw is the one thing here a test cannot
/// otherwise pin down.
CallTimeouts pangeaCallTimeouts({Random? random}) {
  final rng = random ?? Random();
  final span =
      CallDelayedLeave.maxRestart.inMicroseconds -
      CallDelayedLeave.minRestart.inMicroseconds;
  return CallTimeouts(
    delayedEventApplyLeave: CallDelayedLeave.applyLeave,
    delayedEventRestart: Duration(
      microseconds:
          CallDelayedLeave.minRestart.inMicroseconds +
          (rng.nextDouble() * span).round(),
    ),
  );
}
