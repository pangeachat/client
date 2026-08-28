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
    test('a server-written retraction can never be read as a hangup', () {
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
      expect(
        ActiveCall.endedDeliberatelyWithin,
        lessThan(CallDelayedLeave.applyLeave - CallDelayedLeave.maxRestart),
      );
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
      // to ship the day this was written.
      final ours = pangeaCallTimeouts(random: _FixedRandom(0));
      final sdk = CallTimeouts();
      expect(ours.updateExpireTsTimerDuration, sdk.updateExpireTsTimerDuration);
      expect(ours.expireTsBumpDuration, sdk.expireTsBumpDuration);
      expect(ours.callInviteLifetime, sdk.callInviteLifetime);
      expect(ours.activeSpeakerInterval, sdk.activeSpeakerInterval);
    });

    test('it is slower than the SDK default, which is the change', () {
      expect(
        CallDelayedLeave.minRestart,
        greaterThan(CallTimeouts().delayedEventRestart),
      );
    });
  });
}
