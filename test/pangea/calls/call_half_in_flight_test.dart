import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_half_in_flight.dart';

void main() {
  setUp(CallHalfInFlight.resetForTest);

  group('CallHalfInFlight', () {
    test('a held half cannot be claimed twice', () {
      final first = CallHalfInFlight.claim('txn');
      expect(first, isNotNull);
      expect(CallHalfInFlight.claim('txn'), isNull);
      CallHalfInFlight.release(first);
      expect(CallHalfInFlight.claim('txn'), isNotNull);
    });

    test('a stale release cannot drop a newer claim', () {
      final first = CallHalfInFlight.claim('txn');
      CallHalfInFlight.release(first);
      final second = CallHalfInFlight.claim('txn');
      // The first holder releasing again (a duplicate finally) must not free
      // the half the second holder is still working on.
      CallHalfInFlight.release(first);
      expect(CallHalfInFlight.isClaimed('txn'), isTrue);
      CallHalfInFlight.release(second);
      expect(CallHalfInFlight.isClaimed('txn'), isFalse);
    });
  });

  group('raceBounded', () {
    test('returns the work when it wins', () async {
      expect(
        await raceBounded(
          Future.value(7),
          deadline: const Duration(seconds: 1),
          step: 'x',
        ),
        7,
      );
    });

    test(
      'parks at the deadline and kills the attempt before a late landing',
      () async {
        final work = Completer<int>();
        final attempt = AttemptToken();
        final raced = raceBounded(
          work.future,
          deadline: const Duration(milliseconds: 10),
          step: 'upload',
          attempt: attempt,
        );
        await expectLater(raced, throwsA(isA<CallHalfParked>()));
        expect(attempt.live, isFalse);
        // A late landing is never surfaced and never throws unhandled.
        work.complete(1);
        await pumpEventQueue();
      },
    );

    test(
      'cancellation wins with the caller\'s error, synchronously killing the '
      'attempt',
      () async {
        final cancel = Completer<void>();
        final attempt = AttemptToken();
        var observedLiveWhenWorkLanded = true;
        final work = Completer<int>();
        work.future.then((_) => observedLiveWhenWorkLanded = attempt.live);
        final raced = raceBounded(
          work.future,
          deadline: const Duration(minutes: 1),
          step: 'upload',
          canceled: cancel.future,
          onCanceled: () => StateError('canceled'),
          attempt: attempt,
        );
        cancel.complete();
        // The work lands on the very next turn, before the awaiting scope
        // could have resumed: the attempt must already read dead.
        work.complete(1);
        await expectLater(raced, throwsA(isA<StateError>()));
        expect(observedLiveWhenWorkLanded, isFalse);
      },
    );

    test('an attempt token is visible to code run inside it', () async {
      final attempt = AttemptToken();
      AttemptToken? seen;
      await attempt.run(() async {
        await Future<void>.delayed(Duration.zero);
        seen = AttemptToken.current;
      });
      expect(seen, same(attempt));
      expect(AttemptToken.current, isNull);
    });
  });

  test('the upload attempt bound scales with bytes and is capped', () {
    expect(callAudioUploadAttemptBound(0), const Duration(seconds: 60));
    expect(
      callAudioUploadAttemptBound(64 * 1024 * 30),
      const Duration(seconds: 90),
    );
    expect(
      callAudioUploadAttemptBound(60 * 1024 * 1024),
      const Duration(minutes: 5),
    );
  });
}
