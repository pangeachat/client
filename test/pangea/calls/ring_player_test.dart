import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/ring_player.dart';

class _FakeSound implements RingSound {
  final List<String> log = [];
  @override
  Future<void> start() async => log.add('start');
  @override
  Future<void> stop() async => log.add('stop');
  @override
  Future<void> busy() async => log.add('busy');
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
    p.play(r'$ring');
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
    p.play(r'$old');
    await pumpEventQueue();
    p.play(r'$new');
    await pumpEventQueue();
    p.stop(r'$old');
    await pumpEventQueue();
    expect(p.playingForTest, r'$new', reason: 'still ringing the redial');
    expect(sound.log.last, isNot('stop'));
  });

  test('a redial replaces the loop rather than layering it', () async {
    final sound = _FakeSound();
    final p = RingPlayer(sound: sound);
    p.play(r'$old');
    await pumpEventQueue();
    p.play(r'$new');
    await pumpEventQueue();
    expect(sound.log, ['start', 'stop', 'start']);
  });

  test('double-stop and stopAll are safe and final', () async {
    final sound = _FakeSound();
    final p = RingPlayer(sound: sound);
    p.play(r'$ring');
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
    p.play(r'$ring');
    await pumpEventQueue();
    p.busy();
    await pumpEventQueue();
    expect(sound.log, ['start', 'stop', 'busy']);
    expect(p.playingForTest, isNull);
  });

  test('a start superseded by a stop while configuring never plays', () async {
    // The stuck-tone race: a stop that lands while start() is still awaiting the
    // platform configure must cancel the play, not let the loop fire after the
    // caller has already been answered / hung up.
    final configuring = Completer<void>();
    final sound = AssetRingSound()..configureForTest = () => configuring.future;

    final starting = sound.start();
    await sound.stop();
    configuring.complete();
    await starting;

    expect(
      sound.reachedPlayForTest,
      isFalse,
      reason: 'a stop during configure cancels the start',
    );
  });

  test('an unsuperseded start reaches the play', () async {
    final sound = AssetRingSound()..configureForTest = () async {};

    await sound.start();

    expect(sound.reachedPlayForTest, isTrue);
  });

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
