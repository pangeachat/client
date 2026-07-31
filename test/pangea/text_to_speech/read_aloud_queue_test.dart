import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/text_to_speech/read_aloud_queue.dart';

// Unit tests for single-slot read-aloud scheduling.
// Design: client/.github/instructions/message-read-aloud.instructions.md

/// Records what was spoken and lets each utterance be completed on demand, so
/// tests can add items while playback is still in progress.
class _Speaker {
  final List<String> spoken = [];
  final List<Completer<void>> _pending = [];

  Future<void> speak(String item) {
    spoken.add(item);
    final completer = Completer<void>();
    _pending.add(completer);
    return completer.future;
  }

  /// Completes the oldest in-progress utterance and lets the queue react.
  Future<void> finishCurrent() async {
    _pending.removeAt(0).complete();
    await Future.delayed(Duration.zero);
  }
}

void main() {
  late _Speaker speaker;
  bool canPlay = true;

  ReadAloudQueue<String> buildQueue() =>
      ReadAloudQueue<String>(speak: speaker.speak, canPlay: () => canPlay);

  setUp(() {
    speaker = _Speaker();
    canPlay = true;
  });

  test('plays an item immediately when idle', () {
    buildQueue().add('a');
    expect(speaker.spoken, ['a']);
  });

  test(
    'a newer arrival replaces the waiting one rather than queueing',
    () async {
      final queue = buildQueue();
      queue.add('a');
      queue.add('b');
      queue.add('c');

      // Only 'a' is playing; 'b' was displaced by 'c' without ever being spoken.
      expect(speaker.spoken, ['a']);

      await speaker.finishCurrent();
      expect(speaker.spoken, ['a', 'c']);
    },
  );

  test('never holds more than one waiting item', () {
    final queue = buildQueue();
    queue.add('a');
    expect(queue.hasWaiting, isFalse);

    queue.add('b');
    expect(queue.hasWaiting, isTrue);

    queue.add('c');
    expect(queue.hasWaiting, isTrue);
  });

  test('drains the waiting item when playback finishes', () async {
    final queue = buildQueue();
    queue.add('a');
    queue.add('b');

    await speaker.finishCurrent();
    expect(speaker.spoken, ['a', 'b']);
    expect(queue.hasWaiting, isFalse);
  });

  test('ignores new items while playback is not allowed', () {
    canPlay = false;
    buildQueue().add('a');
    expect(speaker.spoken, isEmpty);
  });

  test(
    'does not play the waiting item if playback became disallowed',
    () async {
      final queue = buildQueue();
      queue.add('a');
      queue.add('b');

      canPlay = false;
      await speaker.finishCurrent();

      expect(speaker.spoken, ['a']);
      expect(queue.hasWaiting, isFalse);
    },
  );

  test('clear drops the waiting item and ends playback', () async {
    final queue = buildQueue();
    queue.add('a');
    queue.add('b');

    queue.clear();
    expect(queue.isSpeaking, isFalse);
    expect(queue.hasWaiting, isFalse);

    // The stopped utterance must not resurrect the dropped item on completion.
    await speaker.finishCurrent();
    expect(speaker.spoken, ['a']);
  });

  test('accepts new items again after a clear', () async {
    final queue = buildQueue();
    queue.add('a');
    queue.clear();
    await speaker.finishCurrent();

    queue.add('b');
    expect(speaker.spoken, ['a', 'b']);
  });

  test('a clear mid-playback does not double-play the next item', () async {
    final queue = buildQueue();
    queue.add('a');
    queue.clear();

    queue.add('b');
    await speaker.finishCurrent();

    expect(speaker.spoken, ['a', 'b']);
  });
}
