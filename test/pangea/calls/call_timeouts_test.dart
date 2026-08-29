import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/active_call.dart';
import 'package:fluffychat/routes/chat/calls/call_timeouts.dart';

/// Draws a fixed value, so the ends of the jitter range can be asked for by
/// name instead of hoped for.
class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final double value;

  @override
  double nextDouble() => value;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  int nextInt(int max) => throw UnimplementedError();
}

void main() {
  group('the delayed-leave numbers hold each other up', () {
    test('endedDeliberatelyWithin stays shorter than the earliest server '
        'cleanup', () {
      // ActiveCall reads a membership retraction seen within
      // endedDeliberatelyWithin of the peer leaving as "they pressed end".
      // A device that CRASHED retracts nothing -- the homeserver does it, at
      // the earliest applyLeave - restart after the device stopped
      // heartbeating. Raising the restart interval moves that retraction
      // EARLIER, and once it can arrive inside the window, a crash is reported
      // to the other person as a deliberate hangup and their call is torn down.
      //
      // This is the coupling that makes the two constants one decision: the
      // interval cannot be raised without raising applyLeave to match.
      //
      // The name is the ARITHMETIC and not an outcome, because the outcome
      // does not follow from it. ActiveCall measures its window from the SFU's
      // report of the departure rather than from the death, and the SFU holds a
      // departed participant for its own retention -- so a retention longer
      // than applyLeave - maxRestart puts the server's cleanup first, and the
      // retraction is read as a hangup however wide this gap is. That hole is
      // older than these constants and the SDK's own 18s/4s has it too; it is
      // written down in [CallDelayedLeave] and in endedDeliberatelyWithin's own
      // comment. What this asserts is only that our numbers do not ADD to it.
      // `applyLeave - maxRestart` is the WRONG bound and this test asserted it
      // for a while. It assumes the delayed leave is at most one restart old,
      // which contradicts the invariant asserted below: the interval is chosen
      // so that one restart may be LOST and the membership still survive. A
      // device can therefore die with a leave that is already
      // `2 * maxRestart + requestBudget` old, and the homeserver applies it
      // that much sooner.
      expect(
        ActiveCall.endedDeliberatelyWithin,
        lessThan(
          CallDelayedLeave.applyLeave -
              (CallDelayedLeave.maxRestart * 2 +
                  CallDelayedLeave.requestBudget),
        ),
      );
    });

    test('and it retracts no earlier than the SDK defaults would have', () {
      // The direction is the part this change actually controls. Every drawn
      // interval has to leave the earliest server-written retraction at least
      // as late as the SDK would have put it -- otherwise a load fix would have
      // bought its req/s by making a crash more likely to be reported to the
      // other person as a deliberate hangup.
      // Measured with the same corrected bound on both sides, or the
      // comparison flatters us: the SDK's shorter interval leaves it less
      // exposed to a missed restart than ours does.
      final sdk = CallTimeouts();
      final ours =
          CallDelayedLeave.applyLeave -
          (CallDelayedLeave.maxRestart * 2 + CallDelayedLeave.requestBudget);
      final theirs =
          sdk.delayedEventApplyLeave -
          (sdk.delayedEventRestart * 2 + CallDelayedLeave.requestBudget);
      expect(ours, greaterThan(theirs));
    });

    test('one lost restart never costs the membership', () {
      // The homeserver applies the leave applyLeave after the last SUCCESSFUL
      // restart. At least two attempts have to fit inside that window, minus
      // what one request may take, or a single restart lost to a bad moment on
      // the network drops a live call's membership and the peer watches the
      // caller vanish.
      expect(
        CallDelayedLeave.maxRestart * 2 + CallDelayedLeave.requestBudget,
        lessThanOrEqualTo(CallDelayedLeave.applyLeave),
      );
    });

    test('the range is a range', () {
      expect(CallDelayedLeave.minRestart, greaterThan(Duration.zero));
      expect(
        CallDelayedLeave.minRestart,
        lessThan(CallDelayedLeave.maxRestart),
        reason: 'a single value is what phase-locks a cohort',
      );
    });
  });

  group('what each device draws', () {
    test('lands inside the range at both ends', () {
      expect(
        pangeaCallTimeouts(random: _FixedRandom(0)).delayedEventRestart,
        CallDelayedLeave.minRestart,
      );
      expect(
        pangeaCallTimeouts(random: _FixedRandom(1)).delayedEventRestart,
        CallDelayedLeave.maxRestart,
      );
      for (var seed = 0; seed < 200; seed++) {
        final drawn = pangeaCallTimeouts(
          random: Random(seed),
        ).delayedEventRestart;
        expect(drawn, greaterThanOrEqualTo(CallDelayedLeave.minRestart));
        expect(drawn, lessThanOrEqualTo(CallDelayedLeave.maxRestart));
      }
    });

    test('differs between devices, which is the whole point', () {
      // A fixed interval keeps a class that joined at the top of the hour in
      // lockstep for the length of the call, and turns load that is merely
      // linear into a spike. Two devices have to be able to disagree.
      final drawn = {
        for (var seed = 0; seed < 20; seed++)
          pangeaCallTimeouts(random: Random(seed)).delayedEventRestart,
      };
      expect(drawn.length, greaterThan(1));
    });

    test('the apply-leave delay is asked for exactly, not jittered', () {
      // Only the restart is spread. The deadline itself is what every derived
      // number above is measured against, so it has to be the same everywhere.
      for (var seed = 0; seed < 20; seed++) {
        expect(
          pangeaCallTimeouts(random: Random(seed)).delayedEventApplyLeave,
          CallDelayedLeave.applyLeave,
        );
      }
    });

    test('every other SDK timeout is inherited, not restated', () {
      // Restating them here would freeze this app on whatever the SDK happened
      // to ship the day this was written. Every field the pinned SDK's
      // CallTimeouts has today is listed, not a sample of them -- a sample
      // would have let the other six be restated without anybody noticing.
      // The residual: a field ADDED upstream is not caught, because Dart gives
      // a test no way to enumerate them.
      final ours = pangeaCallTimeouts(random: _FixedRandom(0));
      final sdk = CallTimeouts();
      expect(ours.defaultCallEventLifetime, sdk.defaultCallEventLifetime);
      expect(ours.callInviteLifetime, sdk.callInviteLifetime);
      expect(ours.iceGatheringDelay, sdk.iceGatheringDelay);
      expect(ours.delayBeforeOffer, sdk.delayBeforeOffer);
      expect(ours.updateExpireTsTimerDuration, sdk.updateExpireTsTimerDuration);
      expect(ours.expireTsBumpDuration, sdk.expireTsBumpDuration);
      expect(ours.activeSpeakerInterval, sdk.activeSpeakerInterval);
      expect(ours.makeKeyOnLeaveDelay, sdk.makeKeyOnLeaveDelay);
      expect(ours.makeKeyOnJoinDelay, sdk.makeKeyOnJoinDelay);
      expect(ours.useKeyDelay, sdk.useKeyDelay);
    });

    test('it is slower than the SDK default, which is the change', () {
      expect(
        CallDelayedLeave.minRestart,
        greaterThan(CallTimeouts().delayedEventRestart),
      );
    });
  });
}
