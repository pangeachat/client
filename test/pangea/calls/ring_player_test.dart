import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Level, Logs;

import 'package:fluffychat/routes/chat/calls/ring_player.dart';

/// Records what the keyed player asked of the sound. Its methods return at once,
/// so it pins WHAT was asked and in what order for the synchronous cases.
class _FakeSound implements RingSound {
  final List<String> log = [];
  @override
  Future<void> start(String asset) async => log.add('start');
  @override
  Future<void> stop() async => log.add('stop');
  @override
  Future<void> busy() async => log.add('busy');
  @override
  Future<void> playOnce(String asset) async => log.add('once');
  @override
  Future<void> dispose() async => log.add('dispose');
}

/// A sound whose stop and start settle on a LATER microtask, so a test can see
/// whether a following cue was launched before the stop finished (overlap) or
/// strictly after it (serialized).
class _OrderedSound implements RingSound {
  final List<String> log = [];
  @override
  Future<void> start(String asset) async {
    await Future<void>.delayed(Duration.zero);
    log.add('start');
  }

  @override
  Future<void> stop() async {
    await Future<void>.delayed(Duration.zero);
    log.add('stop');
  }

  @override
  Future<void> busy() async => log.add('busy');
  @override
  Future<void> playOnce(String asset) async => log.add('once');
  @override
  Future<void> dispose() async => log.add('dispose');
}

/// A [RingAudio] under a test's control: it can hold a play open, fail a
/// configure/stop/play, and drive the playback-completion event by hand -- so
/// the player lifecycle can be pinned without a platform audio plugin.
class _FakeRingAudio implements RingAudio {
  _FakeRingAudio({
    this.configureBehavior,
    this.playHold,
    this.throwOnPlay = false,
    this.throwOnStop = false,
  });

  final List<String> log = [];

  /// Extra work configure performs (e.g. throw once), on top of logging.
  final Future<void> Function()? configureBehavior;

  /// If set, the FIRST play blocks on this before returning -- a load a later
  /// stop or start can land in. Later plays do not block, so a test can let an
  /// older play finish LAST, after a newer one has already won.
  final Future<void>? playHold;

  final bool throwOnPlay;
  final bool throwOnStop;

  int _playCount = 0;
  Completer<void>? _complete;

  @override
  Future<void> configure({
    required bool loop,
    required AudioContext context,
  }) async {
    log.add('configure');
    final behavior = configureBehavior;
    if (behavior != null) await behavior();
  }

  @override
  Future<void> play(String asset) async {
    log.add('play:$asset');
    final first = _playCount++ == 0;
    final hold = playHold;
    if (first && hold != null) await hold;
    if (throwOnPlay) throw Exception('play failed');
  }

  @override
  Future<void> stop() async {
    log.add('stop');
    if (throwOnStop) throw Exception('stop failed');
  }

  @override
  Future<void> pause() async => log.add('pause');

  @override
  Future<void> get complete {
    final completer = Completer<void>();
    _complete = completer;
    return completer.future;
  }

  /// Fire the completion event for the play currently being awaited.
  void completeCurrentPlay() => _complete?.complete();

  @override
  Future<void> dispose() async => log.add('dispose');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // audioplayers has no platform here; stub both its global (`init`) and its
  // per-player (`create`) method channels so the real AssetRingSound in the
  // race tests below can be built without an unhandled MissingPluginException
  // surfacing asynchronously into a later test.
  for (final channel in const [
    'xyz.luan/audioplayers.global',
    'xyz.luan/audioplayers',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannel(channel),
          (methodCall) async => null,
        );
  }

  test('plays for a ring and stops for the same ring', () async {
    final sound = _FakeSound();
    final p = RingPlayer(sound: sound);
    p.play(r'$ring', asset: 'sounds/phone.ogg');
    await pumpEventQueue();
    expect(sound.log, ['start']);
    p.stop(r'$ring');
    await pumpEventQueue();
    expect(sound.log, ['start', 'stop']);
  });

  test('a stale stop cannot silence the new ring', () async {
    // A dismissal racing a redial: the old prompt's stop lands after the new
    // prompt started ringing. Keying by ring id makes it a no-op.
    final sound = _FakeSound();
    final p = RingPlayer(sound: sound);
    p.play(r'$old', asset: 'sounds/phone.ogg');
    await pumpEventQueue();
    p.play(r'$new', asset: 'sounds/phone.ogg');
    await pumpEventQueue();
    p.stop(r'$old');
    await pumpEventQueue();
    expect(p.playingForTest, r'$new', reason: 'still ringing the redial');
    expect(sound.log.last, isNot('stop'));
  });

  test('a redial replaces the loop rather than layering it', () async {
    final sound = _FakeSound();
    final p = RingPlayer(sound: sound);
    p.play(r'$old', asset: 'sounds/phone.ogg');
    await pumpEventQueue();
    p.play(r'$new', asset: 'sounds/phone.ogg');
    await pumpEventQueue();
    expect(sound.log, ['start', 'stop', 'start']);
  });

  test('double-stop and stopAll are safe and final', () async {
    final sound = _FakeSound();
    final p = RingPlayer(sound: sound);
    p.play(r'$ring', asset: 'sounds/phone.ogg');
    await pumpEventQueue();
    p.stop(r'$ring');
    p.stop(r'$ring');
    p.stopAll();
    await pumpEventQueue();
    expect(sound.log, ['start', 'stop']);
    expect(p.playingForTest, isNull);
  });

  test('the engaged tone silences any ringing first', () async {
    // A caller hearing their own ringback under the busy note learns
    // nothing; the tone has to arrive on its own.
    final sound = _FakeSound();
    final p = RingPlayer(sound: sound);
    p.play(r'$ring', asset: 'sounds/phone.ogg');
    await pumpEventQueue();
    p.busy();
    await pumpEventQueue();
    expect(sound.log, ['start', 'stop', 'busy']);
    expect(p.playingForTest, isNull);
  });

  test(
    'busy waits for the loop to stop, so ringback and busy never overlap',
    () async {
      // The stop is asynchronous; if busy() launches its tone before the stop
      // settles, the ringback and the busy note sound together. Serialized, the
      // stop finishes first.
      final sound = _OrderedSound();
      final p = RingPlayer(sound: sound);
      p.play(r'$ring', asset: 'sounds/ringback.mp3');
      await pumpEventQueue();
      expect(sound.log, ['start']);
      p.busy();
      await pumpEventQueue();
      expect(
        sound.log,
        ['start', 'stop', 'busy'],
        reason: 'the stop finishes before the busy tone, never under it',
      );
    },
  );

  test(
    'a one-shot after a stop waits for the stop, never overlapping the loop',
    () async {
      final sound = _OrderedSound();
      final p = RingPlayer(sound: sound);
      p.play(r'$ring', asset: 'sounds/ringback.mp3');
      await pumpEventQueue();
      p.stop(r'$ring');
      p.once('sounds/call_ended.mp3');
      await pumpEventQueue();
      expect(sound.log, [
        'start',
        'stop',
        'once',
      ], reason: 'the cut cue plays only after the loop has stopped');
    },
  );

  test('disposing stops the loop, then releases the player', () async {
    final sound = _FakeSound();
    final p = RingPlayer(sound: sound);
    p.play(r'$ring', asset: 'sounds/phone.ogg');
    await pumpEventQueue();
    await p.dispose();
    expect(
      sound.log,
      ['start', 'stop', 'dispose'],
      reason: 'dispose stops the active loop, then disposes the native player',
    );
    expect(p.playingForTest, isNull);
  });

  test('a disposed player accepts no further cues', () async {
    // Every mutator must no-op after dispose, or a busy/once/play could reach
    // the sound AFTER its native player was released (use-after-dispose).
    final sound = _FakeSound();
    final p = RingPlayer(sound: sound);
    await p.dispose();
    p.busy();
    p.once('sounds/call_ended.mp3');
    p.play(r'$ring', asset: 'sounds/phone.ogg');
    await pumpEventQueue();
    expect(sound.log, [
      'stop',
      'dispose',
    ], reason: 'no cue reaches the sound once the player is disposed');
  });

  test('an unsuperseded start reaches the play', () async {
    final sound = AssetRingSound(audioFactory: () => _FakeRingAudio());

    await sound.start('sounds/phone.ogg');

    expect(sound.reachedPlayForTest, isTrue);
  });

  test('a start the stop overtook never plays', () async {
    // The stuck-tone race: a stop issued right after a start supersedes it
    // before its serialized turn comes up, so the loop never sounds -- it does
    // not fire after the caller has already been answered / hung up.
    final sound = AssetRingSound(audioFactory: () => _FakeRingAudio());

    final starting = sound.start('sounds/phone.ogg');
    await sound.stop();
    await starting;

    expect(
      sound.reachedPlayForTest,
      isFalse,
      reason: 'a start the stop overtook stays silent',
    );
  });

  test('a stop during a start configure keeps it from playing', () async {
    // The start has begun and is mid-configure when the stop arrives; the
    // generation re-check after configure keeps it from ever committing to a
    // loop -- the platform-configure window the old code left open.
    final configuring = Completer<void>();
    final handle = _FakeRingAudio(configureBehavior: () => configuring.future);
    final sound = AssetRingSound(audioFactory: () => handle);

    final starting = sound.start('sounds/phone.ogg');
    await pumpEventQueue();
    expect(handle.log, ['configure'], reason: 'the start is mid-configure');
    final stopping = sound.stop();
    configuring.complete();
    await Future.wait([starting, stopping]);

    expect(
      sound.reachedPlayForTest,
      isFalse,
      reason: 'a stop during configure keeps the start from ever playing',
    );
    expect(handle.log, isNot(contains('play:sounds/phone.ogg')));
  });

  test('a stop after a started loop stops it in order', () async {
    // The start's play is in flight when the stop arrives. Serialized on the
    // loop chain, the stop runs AFTER the play, so the loop ends stopped --
    // never a play racing a stop on the shared player.
    final playing = Completer<void>();
    final handle = _FakeRingAudio(playHold: playing.future);
    final sound = AssetRingSound(audioFactory: () => handle);

    final starting = sound.start('sounds/phone.ogg');
    await pumpEventQueue();
    expect(handle.log, [
      'configure',
      'play:sounds/phone.ogg',
    ], reason: 'the loop started and is holding on its play');
    final stopping = sound.stop();
    playing.complete();
    await Future.wait([starting, stopping]);

    expect(handle.log, [
      'configure',
      'play:sounds/phone.ogg',
      'stop',
    ], reason: 'the stop runs after the play, so the loop ends stopped');
  });

  test('a stale start neither plays nor stops when a newer one wins', () async {
    // Two starts race on the shared player; the newer supersedes the older
    // before the older's turn. The stale start does NOTHING -- it neither plays
    // its asset nor stops the newer cue that owns the player now.
    final handle = _FakeRingAudio();
    final sound = AssetRingSound(audioFactory: () => handle);

    final older = sound.start('sounds/ringback.mp3');
    final newer = sound.start('sounds/call.ogg');
    await Future.wait([older, newer]);

    expect(
      handle.log,
      ['configure', 'play:sounds/call.ogg'],
      reason: 'only the newer cue reaches the player; no stale play, no stop',
    );
  });

  test(
    'a start waits for configuration to complete, and retries a failed one',
    () async {
      var configureCalls = 0;
      final handle = _FakeRingAudio(
        configureBehavior: () async {
          configureCalls++;
          if (configureCalls == 1) throw Exception('configure failed');
        },
      );
      final sound = AssetRingSound(audioFactory: () => handle);

      await sound.start('sounds/phone.ogg');
      expect(
        sound.reachedPlayForTest,
        isFalse,
        reason: 'a failed configuration does not reach the play',
      );

      await sound.start('sounds/phone.ogg');
      expect(
        configureCalls,
        2,
        reason: 'the failed configuration is retried, not cached as done',
      );
      expect(sound.reachedPlayForTest, isTrue);
    },
  );

  test('a one-shot player is disposed even when playback throws', () async {
    final handle = _FakeRingAudio(throwOnPlay: true);
    final sound = AssetRingSound(audioFactory: () => handle);

    await sound.playOnce('sounds/call_ended.mp3');

    expect(handle.log, [
      'configure',
      'play:sounds/call_ended.mp3',
      'dispose',
    ], reason: 'the throwaway player is disposed on the error path too');
  });

  test(
    'a one-shot is torn down on playback completion, not a fixed timer',
    () async {
      final handle = _FakeRingAudio();
      final sound = AssetRingSound(audioFactory: () => handle);

      final playing = sound.playOnce('sounds/call_ended.mp3');
      await pumpEventQueue();
      expect(handle.log, [
        'configure',
        'play:sounds/call_ended.mp3',
      ], reason: 'the cue is playing and not yet torn down');

      // Draining the queue is not enough: without a completion event the cue is
      // held open, so a longer asset is never cut off.
      await pumpEventQueue();
      expect(handle.log, isNot(contains('dispose')));

      handle.completeCurrentPlay();
      await pumpEventQueue();
      expect(
        handle.log,
        contains('dispose'),
        reason: 'the completion event drives teardown',
      );
      await playing;
    },
  );

  test(
    'a failed stop is surfaced and recovers, not silently swallowed',
    () async {
      final handle = _FakeRingAudio(throwOnStop: true);
      final sound = AssetRingSound(audioFactory: () => handle);
      Logs().outputEvents.clear();

      await sound.stop();

      expect(
        handle.log,
        contains('pause'),
        reason: 'a failed stop attempts recovery, not a silent swallow',
      );
      expect(
        Logs().outputEvents.any(
          (e) => e.level == Level.warning && e.title.contains('failed to stop'),
        ),
        isTrue,
        reason: 'the stop failure is logged, not swallowed',
      );
    },
  );

  test('the banner raises and drops a return offer in exactly two places', () {
    // Same class as the prompt above. One path -- replacing a stale ring for
    // the same room -- assigned the offer directly and armed no watcher, so
    // that banner could outlive the call it pointed at for ever; four of the
    // clear sites left the watcher running on a withdrawn offer. _showOffer
    // and _clearOffer are the only two places allowed to touch it.
    final source = File(
      'lib/routes/chat/calls/incoming_call_banner.dart',
    ).readAsStringSync();
    final assignments = RegExp(
      r'_rejoin\s*=(?![=>])',
    ).allMatches(source).length;
    expect(
      assignments,
      2,
      reason:
          'offers go up through _showOffer and come down through '
          '_clearOffer, which is what guarantees the watcher',
    );
  });

  test('the banner assigns its prompt in exactly one place', () {
    // The four historical assignment sites each stopped (or forgot to stop)
    // the sound their own way. The setter is the single choke point; a new
    // direct assignment reintroduces the class of bug this pins shut.
    final source = File(
      'lib/routes/chat/calls/incoming_call_banner.dart',
    ).readAsStringSync();
    final assignments = RegExp(r'_ringing\s*=(?!=)').allMatches(source).length;
    expect(
      assignments,
      1,
      reason: 'every prompt mutation must go through _showRing',
    );
  });
}
