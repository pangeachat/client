import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/text_to_speech/tts_device_utterance.dart';

/// The outcome rules for one device utterance (#8455).
///
/// One rule decides every end signal: audio was heard iff the engine reported a
/// start; otherwise it is a cancel iff the app asked for the stop, and a
/// failure if nobody did. These pin that rule per signal, because each signal
/// arrives from a different platform in a different shape (Chrome reports an
/// interruption as an *error*; iOS as a *cancel*; Android resolves the speak
/// future with 0) and the controller must read them all the same way.
void main() {
  const timeout = Duration(seconds: 3);
  TtsDeviceUtterance fresh() => TtsDeviceUtterance(startTimeout: timeout);

  group('audio heard: started, then any end signal', () {
    test('completion → played', () async {
      final u = fresh()
        ..onEngineStart()
        ..onEngineComplete();
      expect(await u.outcome, TtsDeviceOutcome.played);
      expect(u.engineHasEnded, isTrue);
    });

    test('cancel handler → played (cut off, but heard)', () async {
      final u = fresh()
        ..onEngineStart()
        ..requestStop()
        ..onEngineCancel();
      expect(await u.outcome, TtsDeviceOutcome.played);
    });

    test("Chrome's error('interrupted') → played", () async {
      final u = fresh()
        ..onEngineStart()
        ..requestStop()
        ..onEngineError('interrupted');
      expect(await u.outcome, TtsDeviceOutcome.played);
    });

    test(
      'an engine error mid-utterance → played (nothing to rescue)',
      () async {
        // The learner heard part of the word; replaying it from the backend
        // would be a second, unasked-for playback.
        final u = fresh()
          ..onEngineStart()
          ..onEngineError('synthesis-failed');
        expect(await u.outcome, TtsDeviceOutcome.played);
      },
    );

    test('speak future resolved after a start → played', () async {
      final u = fresh()
        ..onEngineStart()
        ..onSpeakReturned();
      expect(await u.outcome, TtsDeviceOutcome.played);
      // The speak future is not an engine event: `stop()` still waits for the
      // engine's own confirmation.
      expect(u.engineHasEnded, isFalse);
    });

    test('an interruption from outside the app after a start → played', () {
      // Nobody in the app asked for a stop (an OS audio interruption, another
      // page calling `speechSynthesis.cancel()`); the learner still heard it.
      final u = fresh()
        ..onEngineStart()
        ..onEngineError('interrupted');
      expect(u.outcome, completion(TtsDeviceOutcome.played));
    });
  });

  group('silence asked for: stopped before it started', () {
    test('cancel handler after a stop request → cancelled', () async {
      final u = fresh()
        ..requestStop()
        ..onEngineCancel();
      expect(await u.outcome, TtsDeviceOutcome.cancelled);
    });

    test(
      "Chrome's error('canceled') after a stop request → cancelled",
      () async {
        final u = fresh()
          ..requestStop()
          ..onEngineError('canceled');
        expect(await u.outcome, TtsDeviceOutcome.cancelled);
      },
    );

    test('Android: speak resolved 0 after a stop request → cancelled', () async {
      // Android's `stop` resolves the pending speak result before onStop fires;
      // a stopped-before-start utterance must not read as a failure to rescue.
      final u = fresh()
        ..requestStop()
        ..onSpeakReturned();
      expect(await u.outcome, TtsDeviceOutcome.cancelled);
    });

    test('a stop the engine never confirmed → cancelled', () async {
      final u = fresh()
        ..requestStop()
        ..onStopUnconfirmed();
      expect(await u.outcome, TtsDeviceOutcome.cancelled);
    });

    test('a stop the engine never confirmed, after a start → played', () async {
      final u = fresh()
        ..onEngineStart()
        ..requestStop()
        ..onStopUnconfirmed();
      expect(await u.outcome, TtsDeviceOutcome.played);
    });
  });

  group('failed: never spoke and nobody asked it to stop', () {
    test("engine error before any start ('not-allowed') → failed", () async {
      final u = fresh()..onEngineError('not-allowed');
      expect(await u.outcome, TtsDeviceOutcome.failed);
      expect(u.engineHasEnded, isTrue);
    });

    test('a stale cancel from the previous utterance → failed', () async {
      // The web plugin reuses one utterance object; the previous word's
      // `interrupted` can land after this one was installed. No stop was
      // requested for THIS utterance and it never started, so it never spoke.
      final u = fresh()..onEngineError('interrupted');
      expect(await u.outcome, TtsDeviceOutcome.failed);
    });

    test('a stale cancel handler call → failed', () async {
      final u = fresh()..onEngineCancel();
      expect(await u.outcome, TtsDeviceOutcome.failed);
    });

    test('completion without a start → failed', () async {
      // The previous utterance's `end` (browsers that fire `end` on cancel)
      // completing this one's speak future: nothing was spoken.
      final u = fresh()..onEngineComplete();
      expect(await u.outcome, TtsDeviceOutcome.failed);
    });

    test('speak future resolved without a start → failed', () async {
      final u = fresh()..onSpeakReturned();
      expect(await u.outcome, TtsDeviceOutcome.failed);
    });

    test('speak future threw → failed, even after a start', () async {
      final u = fresh()
        ..onEngineStart()
        ..onSpeakThrew();
      expect(await u.outcome, TtsDeviceOutcome.failed);
    });
  });

  group('start watchdog', () {
    // Real time, kept short: the watchdog is a plain `Timer` and the rule
    // under test is what it does when it fires, not how long it waits.
    const short = Duration(milliseconds: 30);
    TtsDeviceUtterance quick() => TtsDeviceUtterance(startTimeout: short);
    Future<void> wait(Duration d) => Future<void>.delayed(d);

    test('no start within the timeout → failed', () async {
      final u = quick()..arm();
      TtsDeviceOutcome? outcome;
      unawaited(u.outcome.then((o) => outcome = o));

      await wait(short ~/ 3);
      expect(outcome, isNull, reason: 'still waiting for the engine');

      await wait(short * 2);
      expect(outcome, TtsDeviceOutcome.failed);
      // The engine said nothing: `stop()` cannot rely on a confirmation.
      expect(u.engineHasEnded, isFalse);
    });

    test('a start disarms it', () async {
      final u = quick()..arm();
      TtsDeviceOutcome? outcome;
      unawaited(u.outcome.then((o) => outcome = o));

      await wait(short ~/ 3);
      u.onEngineStart();
      await wait(short * 2);
      expect(outcome, isNull, reason: 'a long word is not a failure');

      u.onEngineComplete();
      await wait(Duration.zero);
      expect(outcome, TtsDeviceOutcome.played);
    });

    test('a stop request during the wait → cancelled, not failed', () async {
      final u = quick()..arm();
      u.requestStop();
      expect(await u.outcome, TtsDeviceOutcome.cancelled);
    });

    test('dispose releases the timer', () async {
      final u = quick()..arm();
      u.dispose();
      await wait(short * 2);
      expect(u.isSettled, isFalse);
    });
  });

  group('settles once', () {
    test('later signals do not change the outcome', () async {
      final u = fresh()
        ..onEngineStart()
        ..onEngineComplete()
        // A stale error arriving afterwards.
        ..onEngineError('not-allowed')
        ..onSpeakThrew();
      expect(await u.outcome, TtsDeviceOutcome.played);
    });

    test('a failure is not upgraded by a late start', () async {
      final u = fresh()
        ..onEngineError('not-allowed')
        ..onEngineStart()
        ..onEngineComplete();
      expect(await u.outcome, TtsDeviceOutcome.failed);
    });
  });
}
