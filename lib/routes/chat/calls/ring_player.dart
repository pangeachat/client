import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:matrix/matrix.dart' show Logs;

/// The sound behind a keyed ring lifecycle, seamed so the lifecycle can be
/// tested without a platform audio plugin.
abstract class RingSound {
  /// Loop [asset] until [stop].
  Future<void> start(String asset);
  Future<void> stop();

  /// The short double note a caller hears when the other line is busy. Not a
  /// loop: it says one thing and stops.
  Future<void> busy();

  /// Play [asset] ONCE -- a one-shot cue (a call cut, #8807), not a loop.
  Future<void> playOnce(String asset);
}

/// Plays bundled sounds through audioplayers.
///
/// The looped cue plays under the Android usage this sound was built for: an
/// incoming ring is a notification-ringtone, so silent mode and Do Not Disturb
/// are the OS's decision; a caller's own call cues (#8807) are the call's own
/// signalling, heard even when ringtones are silenced. On the web the first
/// play can be refused without a user gesture -- that refusal is swallowed on
/// purpose: a visible ring without sound beats a crash.
class AssetRingSound implements RingSound {
  final AudioPlayer _player = AudioPlayer();
  bool _configured = false;

  /// Bumped by every [stop] and every fresh [start], so a [start] superseded
  /// WHILE it awaited [_configure] does not play a loop nobody wants any more --
  /// the stuck-tone race a stop landing inside that await opens, on the caller
  /// cues (#8807) and the incoming ring alike.
  int _generation = 0;

  /// Test seam: replaces the platform configure so a test can hold [start]
  /// inside its await and land a [stop] in the gap.
  @visibleForTesting
  Future<void> Function()? configureForTest;

  /// Test seam: set the moment a [start] commits to playing, so a test can
  /// prove a superseded start never reaches it.
  @visibleForTesting
  bool reachedPlayForTest = false;

  /// The Android usage every cue from this sound plays under (see the class
  /// doc). Per-sound, not per-cue: an incoming-ring sound is a ringtone, a
  /// caller's call-cue sound is call signalling.
  final AndroidUsageType _usage;

  AssetRingSound({
    AndroidUsageType usage = AndroidUsageType.notificationRingtone,
  }) : _usage = usage;

  /// A caller's own call cues (#8807), played under the call-signalling usage so
  /// the caller hears them even with ringtones silenced.
  AssetRingSound.callSignalling()
    : this(usage: AndroidUsageType.voiceCommunicationSignalling);

  AudioContext _context() => AudioContext(
    android: AudioContextAndroid(
      usageType: _usage,
      contentType: AndroidContentType.sonification,
      audioFocus: AndroidAudioFocus.gainTransient,
    ),
    iOS: AudioContextIOS(),
  );

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setAudioContext(_context());
  }

  @override
  Future<void> start(String asset) async {
    final generation = ++_generation;
    try {
      await (configureForTest ?? _configure)();
      // A stop -- or a newer start -- that landed while we were configuring has
      // moved the generation on; this start is stale and must NOT play a loop
      // the caller no longer wants.
      if (generation != _generation) return;
      reachedPlayForTest = true;
      await _player.play(AssetSource(asset));
    } catch (e) {
      // Autoplay refused (web without a gesture), or no audio device. The cue
      // is an enhancement, not the mechanism.
      Logs().i('Ring sound not played: $e');
    }
  }

  @override
  Future<void> stop() async {
    // Supersede any start still inside its configure await, so it cannot play
    // after this stop.
    _generation++;
    try {
      await _player.stop();
    } catch (_) {}
  }

  @override
  Future<void> busy() =>
      _oneShot('sounds/notification.ogg', times: 2, gapMs: 450);

  @override
  Future<void> playOnce(String asset) => _oneShot(asset, times: 1);

  /// Plays [asset] [times] on a THROWAWAY player, so a one-shot cue never
  /// touches -- or gets stopped alongside -- the looping player.
  Future<void> _oneShot(
    String asset, {
    required int times,
    int gapMs = 0,
  }) async {
    try {
      final beeper = AudioPlayer();
      await beeper.setReleaseMode(ReleaseMode.stop);
      await beeper.setAudioContext(_context());
      for (var i = 0; i < times; i++) {
        if (i > 0) {
          await Future<void>.delayed(Duration(milliseconds: gapMs));
        }
        await beeper.play(AssetSource(asset));
      }
      // Let the last play be heard before the throwaway player is torn down.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await beeper.dispose();
    } catch (e) {
      // A cue is a courtesy; the words on screen are the message.
      Logs().i('Call cue not played: $e');
    }
  }
}

/// A keyed player for ONE looping cue at a time plus one-shot cues.
///
/// Keyed by an id so a stale stop -- a dismissal racing a redial's replacement,
/// or a switch from ringback to the reconnecting loop (#8807) -- can never
/// silence the loop that replaced it: [stop] acts only when the id it names is
/// the one playing. The incoming ring keys on the ring event; a caller's own
/// cues key on the call.
class RingPlayer {
  final RingSound _sound;

  RingPlayer({RingSound? sound}) : _sound = sound ?? AssetRingSound();

  String? _playingFor;

  /// Loops [asset] for [ringId]. The same id is a no-op; a different id replaces
  /// the loop (stop, then start) so a redial -- or a switch to another cue --
  /// plays afresh.
  void play(String ringId, {required String asset}) {
    if (_playingFor == ringId) return;
    final replacing = _playingFor != null;
    _playingFor = ringId;
    unawaited(() async {
      if (replacing) await _sound.stop();
      // Guarded: the cue may already have gone while the stop settled.
      if (_playingFor == ringId) await _sound.start(asset);
    }());
  }

  /// Stops the loop IF [ringId] is the one playing. Idempotent; a stale id is a
  /// no-op by design.
  void stop(String ringId) {
    if (_playingFor != ringId) return;
    _playingFor = null;
    unawaited(_sound.stop());
  }

  /// The engaged tone, once. Whatever was looping stops first: a caller hearing
  /// their own ringback over the busy note learns nothing.
  void busy() {
    stopAll();
    unawaited(_sound.busy());
  }

  /// A one-shot cue -- the call-cut tone (#8807) -- once. Plays on a throwaway
  /// player, so it does NOT stop the loop; the caller stops the loop through
  /// [stop]/[stopAll] as the call resolves, and this only says "it ended".
  void once(String asset) {
    unawaited(_sound.playOnce(asset));
  }

  /// Stops whatever is looping. For dispose and account switches.
  void stopAll() {
    if (_playingFor == null) return;
    _playingFor = null;
    unawaited(_sound.stop());
  }

  @visibleForTesting
  String? get playingForTest => _playingFor;
}
