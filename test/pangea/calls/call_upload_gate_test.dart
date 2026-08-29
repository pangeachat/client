import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/calls/call_upload_gate.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// Short enough that a test need not wait a real cooldown out, long enough that
/// a loaded machine does not trip them. Every one of these is a real wall-clock
/// wait: the gate's whole job is to make callers wait, so a faked clock would
/// test something else.
const _openFor = Duration(milliseconds: 60);
const _budget = Duration(milliseconds: 300);

/// A 429 and a 503 as this app actually raises them.
PangeaHttpException _http(int status) =>
    PangeaHttpException(statusCode: status, method: 'POST', path: '/x');

PcmChunk _chunk(int index) => PcmChunk(
  // Loud enough to survive the speech trim, which drops a chunk it reads as
  // silence before any request is made.
  pcm: Uint8List.view(
    Int16List.fromList(
      List<int>.generate(16000, (i) => i.isEven ? 9000 : -9000),
    ).buffer,
  ),
  sampleRate: 16000,
  channels: 1,
  index: index,
  startedAtMs: 0,
);

final SpeechToTextResponseModel _silent = SpeechToTextResponseModel.fromJson({
  'lang_code': 'es',
  'results': [],
});

void main() {
  group('the concurrency cap', () {
    test(
      'holds a caller past the cap until one of the others is done',
      () async {
        final gate = CallUploadGate(maxInFlight: 3, openFor: _openFor);
        final running = <int, Completer<void>>{};
        var started = 0;

        Future<void> send(int id) {
          running[id] = Completer<void>();
          return gate.run(() async {
            started++;
            await running[id]!.future;
          }, within: _budget);
        }

        final first = [for (var i = 0; i < 3; i++) send(i)];
        await pumpEventQueue();
        expect(started, 3, reason: 'the cap is three, not two');

        final fourth = send(3);
        await pumpEventQueue();
        expect(
          started,
          3,
          reason: 'the fourth upload must not be issued while three are out',
        );

        running[0]!.complete();
        await first[0];
        await pumpEventQueue();
        expect(started, 4, reason: 'the freed permit goes to the one waiting');

        for (var i = 1; i < 4; i++) {
          running[i]!.complete();
        }
        await Future.wait([...first.skip(1), fourth]);
        expect(gate.inFlight, 0);
      },
    );

    test('a permit is given back when the request is abandoned, not when it '
        'finally answers', () async {
      // Nothing this app sends is abortable, so a timed-out upload keeps its
      // socket. A permit tied to the raw future would be held for however long
      // the request took to give up on its own -- sixty seconds through
      // `SpeechToTextRepo`, and for ever behind a transcriber with no deadline,
      // which is what the fake here is. Three of those and the device stops
      // sending. The permit has to come back when we stop WAITING.
      final gate = CallUploadGate(maxInFlight: 3, openFor: _openFor);

      await expectLater(
        gate.run(
          () => Completer<void>().future,
          within: const Duration(milliseconds: 40),
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(gate.inFlight, 0);
      // And the gate still works afterwards.
      await gate.run(() async {}, within: _budget);
    });

    test('a waiter that gives up is taken out of the queue', () async {
      // `Future.timeout` only stops US waiting. Left in the queue, the
      // abandoned waiter is handed the next permit and nobody is there to give
      // it back -- the cap shrinks by one, permanently, for every attempt that
      // ever timed out.
      final gate = CallUploadGate(maxInFlight: 2, openFor: _openFor);
      final held = [Completer<void>(), Completer<void>()];
      final busy = [
        for (final c in held) gate.run(() => c.future, within: _budget),
      ];
      await pumpEventQueue();

      await expectLater(
        gate.run(() async {}, within: const Duration(milliseconds: 30)),
        throwsA(isA<TimeoutException>()),
      );

      for (final c in held) {
        c.complete();
      }
      await Future.wait(busy);
      expect(
        gate.inFlight,
        0,
        reason: 'the abandoned waiter must not be holding a permit',
      );

      var ran = 0;
      await Future.wait([
        for (var i = 0; i < 2; i++)
          gate.run(() async => ran++, within: _budget),
      ]);
      expect(ran, 2, reason: 'both permits are still there');
    });
  });

  group('the circuit breaker', () {
    test(
      'opens only after the server has failed several times in a row',
      () async {
        final gate = CallUploadGate(failuresToOpen: 3, openFor: _openFor);

        for (var i = 0; i < 2; i++) {
          await expectLater(
            gate.run(() async => throw _http(503), within: _budget),
            throwsA(isA<PangeaHttpException>()),
          );
          expect(gate.isOpen, isFalse, reason: 'two is a blip, not an outage');
        }

        await expectLater(
          gate.run(() async => throw _http(503), within: _budget),
          throwsA(isA<PangeaHttpException>()),
        );
        expect(gate.isOpen, isTrue);
      },
    );

    test('a 429 and a timeout count; a 4xx does not', () async {
      final gate = CallUploadGate(failuresToOpen: 2, openFor: _openFor);

      await expectLater(
        gate.run(() async => throw _http(400), within: _budget),
        throwsA(isA<PangeaHttpException>()),
      );
      await expectLater(
        gate.run(() async => throw _http(404), within: _budget),
        throwsA(isA<PangeaHttpException>()),
      );
      expect(
        gate.isOpen,
        isFalse,
        reason: 'a bad request says nothing about the server\'s load',
      );

      await expectLater(
        gate.run(() async => throw _http(429), within: _budget),
        throwsA(isA<PangeaHttpException>()),
      );
      await expectLater(
        gate.run(
          () => Completer<void>().future,
          within: const Duration(milliseconds: 30),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(
        gate.isOpen,
        isTrue,
        reason: 'a 429 and a hang are both the server',
      );
    });

    test(
      'a success already in flight when it opened does not close it',
      () async {
        // The upload was admitted while the breaker was shut, so the failures
        // that opened it happened AFTER it went out -- it is not evidence about
        // the state that opened the breaker and it is not the probe. Closing on
        // it would let every waiter through with no cooldown at all; merely
        // clearing the failure count would be worse, because the probe that
        // followed could then fail without reaching the threshold again and the
        // doors would stay open on a backend still down.
        final gate = CallUploadGate(
          maxInFlight: 3,
          failuresToOpen: 2,
          openFor: _openFor,
        );
        final slow = Completer<void>();
        final inFlight = gate.run(() => slow.future, within: _budget);
        await pumpEventQueue();

        for (var i = 0; i < 2; i++) {
          await expectLater(
            gate.run(() async => throw _http(503), within: _budget),
            throwsA(isA<PangeaHttpException>()),
          );
        }
        expect(gate.isOpen, isTrue);
        final counted = gate.consecutiveFailures;

        slow.complete();
        await inFlight;

        expect(
          gate.isOpen,
          isTrue,
          reason: 'the cooldown still has to be served',
        );
        expect(
          gate.consecutiveFailures,
          counted,
          reason: 'and the run that opened it still stands',
        );
      },
    );

    test('a 4xx in between breaks the run too', () async {
      // Consecutive has to mean consecutive. A 4xx is the server ANSWERING, so
      // 503-400-503 is not two failures in a row -- and a breaker that opened
      // on it would throttle a device against a backend that was serving
      // perfectly well between two blips.
      final gate = CallUploadGate(failuresToOpen: 2, openFor: _openFor);

      for (final status in [503, 400, 503]) {
        await expectLater(
          gate.run(() async => throw _http(status), within: _budget),
          throwsA(isA<PangeaHttpException>()),
        );
      }

      expect(gate.consecutiveFailures, 1, reason: 'the 400 broke the run');
      expect(gate.isOpen, isFalse);
    });

    test('a success in between clears the run', () async {
      final gate = CallUploadGate(failuresToOpen: 2, openFor: _openFor);

      await expectLater(
        gate.run(() async => throw _http(500), within: _budget),
        throwsA(isA<PangeaHttpException>()),
      );
      await gate.run(() async {}, within: _budget);
      expect(gate.consecutiveFailures, 0);

      await expectLater(
        gate.run(() async => throw _http(500), within: _budget),
        throwsA(isA<PangeaHttpException>()),
      );
      expect(gate.isOpen, isFalse, reason: 'the run was broken by the success');
    });

    test('being refused is not evidence about the server', () async {
      // The refusal a caller sees is a TimeoutException, and so is a request
      // that hung -- but only one of them reached the server. Counting the
      // refusal would let the breaker hold itself open off its own refusals,
      // for ever, with nothing able to close it.
      final gate = CallUploadGate(failuresToOpen: 2, openFor: _openFor);
      await expectLater(
        gate.run(() async => throw _http(500), within: _budget),
        throwsA(isA<PangeaHttpException>()),
      );
      await expectLater(
        gate.run(() async => throw _http(500), within: _budget),
        throwsA(isA<PangeaHttpException>()),
      );
      expect(gate.isOpen, isTrue);
      final before = gate.consecutiveFailures;

      var reached = false;
      await expectLater(
        gate.run(
          () async => reached = true,
          // Less than the cooldown, so this one can only ever be refused.
          within: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(reached, isFalse, reason: 'nothing went to the server');
      expect(gate.consecutiveFailures, before);
    });

    test(
      'a caller with no budget left is refused without being counted',
      () async {
        // The other end of the same rule, and the one path that reaches it with
        // the breaker CLOSED: a permit is free, the breaker is shut, and there is
        // still no time to send in. Nothing may go out, and nothing may be
        // recorded -- the gate has learned nothing about the server.
        final gate = CallUploadGate(failuresToOpen: 1, openFor: _openFor);
        var reached = false;

        await expectLater(
          gate.run(() async => reached = true, within: Duration.zero),
          throwsA(isA<TimeoutException>()),
        );

        expect(reached, isFalse);
        expect(gate.consecutiveFailures, 0);
        expect(gate.isOpen, isFalse);
        expect(gate.inFlight, 0, reason: 'and the permit came back');
      },
    );

    test('audio is not dropped while it is open: the caller waits for the '
        'probe slot', () async {
      final gate = CallUploadGate(failuresToOpen: 1, openFor: _openFor);
      await expectLater(
        gate.run(() async => throw _http(503), within: _budget),
        throwsA(isA<PangeaHttpException>()),
      );
      expect(gate.isOpen, isTrue);

      final at = Stopwatch()..start();
      await gate.run(() async {}, within: _budget);
      at.stop();

      expect(
        at.elapsed,
        greaterThanOrEqualTo(_openFor * 0.7),
        reason: 'it waited the cooldown out rather than being refused',
      );
      expect(gate.isOpen, isFalse, reason: 'the probe succeeded, so it closed');
    });

    test('exactly one caller probes; the rest wait for its verdict', () async {
      final gate = CallUploadGate(failuresToOpen: 1, openFor: _openFor);
      await expectLater(
        gate.run(() async => throw _http(503), within: _budget),
        throwsA(isA<PangeaHttpException>()),
      );

      var reached = 0;
      final probe = Completer<void>();
      final both = [
        for (var i = 0; i < 2; i++)
          gate.run(() {
            reached++;
            return probe.future;
          }, within: _budget),
      ];

      await Future<void>.delayed(_openFor * 2);
      expect(
        reached,
        1,
        reason: 'a failing server is asked by one of us, once',
      );

      probe.complete();
      await Future.wait(both);
      expect(reached, 2, reason: 'the other went once the probe had answered');
    });

    test(
      'a probe that fails re-opens it rather than letting everyone through',
      () async {
        final gate = CallUploadGate(failuresToOpen: 1, openFor: _openFor);
        await expectLater(
          gate.run(() async => throw _http(503), within: _budget),
          throwsA(isA<PangeaHttpException>()),
        );

        await expectLater(
          gate.run(() async => throw _http(503), within: _budget),
          throwsA(isA<PangeaHttpException>()),
        );
        expect(
          gate.isOpen,
          isTrue,
          reason: 'the probe found the server still failing',
        );

        var reached = false;
        await expectLater(
          gate.run(
            () async => reached = true,
            within: const Duration(milliseconds: 20),
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(reached, isFalse, reason: 'a fresh cooldown, not an open door');
      },
    );

    test('a probe that comes back 4xx does not count as the server being '
        'well again', () async {
      // A 4xx says nothing about load, so it does not advance the failure count
      // -- and that is exactly why the probe path has to re-open on ANY failure
      // rather than on a fresh count. Read as "the server answered, so it is
      // fine", one malformed chunk would empty the cooldown and let every
      // waiter through at a backend that is still down.
      final gate = CallUploadGate(failuresToOpen: 2, openFor: _openFor);
      for (var i = 0; i < 2; i++) {
        await expectLater(
          gate.run(() async => throw _http(503), within: _budget),
          throwsA(isA<PangeaHttpException>()),
        );
      }
      expect(gate.isOpen, isTrue);
      final counted = gate.consecutiveFailures;

      await expectLater(
        gate.run(() async => throw _http(400), within: _budget),
        throwsA(isA<PangeaHttpException>()),
      );

      expect(
        gate.consecutiveFailures,
        counted,
        reason: 'a bad request is still not a statement about load',
      );
      expect(
        gate.isOpen,
        isTrue,
        reason: 'and the breaker stayed open against everyone else',
      );
    });
  });

  group('what the sink records when the gate refuses', () {
    setUp(CallUploadGate.resetShared);

    test('a chunk it could not send is LOST, never suppressed', () async {
      // The four states are captured / transcribed / lost / suppressed, and the
      // difference between the last two is the whole honesty of the half this
      // writes. Suppressed means THIS DEVICE looked at the audio and found
      // nothing said; a chunk we never got to send is not that, and recording
      // it as that would present a gap as a silence.
      final gate = CallUploadGate(failuresToOpen: 1, openFor: _openFor);
      var sent = 0;
      final sink = CallTranscriptSink(
        userL1: 'en',
        userL2: 'es',
        gate: gate,
        transcribe: (_) async {
          sent++;
          throw _http(503);
        },
      );

      await expectLater(
        sink.deliver(_chunk(0), within: _budget),
        throwsA(isA<PangeaHttpException>()),
      );
      expect(gate.isOpen, isTrue);

      await expectLater(
        sink.deliver(
          _chunk(1),
          // Shorter than the cooldown, so this chunk can only be refused.
          within: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(sent, 1, reason: 'the second chunk never reached the route');
      expect(sink.chunksCaptured, 2);
      expect(sink.chunksLost, 2);
      expect(
        sink.chunksSuppressed,
        0,
        reason: 'we never examined that audio and found it empty',
      );
    });

    test('a delivery goes through the device gate, not around it', () async {
      // The sink is the only place the request is made, so a gate the sink did
      // not consult is a cap on nothing.
      final gate = CallUploadGate(maxInFlight: 2, openFor: _openFor);
      final held = [Completer<void>(), Completer<void>()];
      final busy = [
        for (final c in held) gate.run(() => c.future, within: _budget),
      ];
      await pumpEventQueue();

      var sent = 0;
      final sink = CallTranscriptSink(
        userL1: 'en',
        userL2: 'es',
        gate: gate,
        transcribe: (_) async {
          sent++;
          return _silent;
        },
      );

      final delivery = sink.deliver(_chunk(0), within: _budget);
      await pumpEventQueue();
      expect(sent, 0, reason: 'the cap was full, so nothing was uploaded');

      for (final c in held) {
        c.complete();
      }
      await Future.wait(busy);
      await delivery;
      expect(sent, 1);
    });
  });
}
