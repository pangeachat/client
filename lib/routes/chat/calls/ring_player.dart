import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:matrix/matrix.dart' show Logs;

/// The looping sound itself, behind a seam so the keyed lifecycle can be
/// tested without a platform audio plugin.
abstract class RingSound {
  Future<void> start();
  Future<void> stop();

  /// The short double note a caller hears when the other line is busy. Not a
  /// loop: it says one thing and stops.
  Future<void> busy();
}

/// The bundled ringtone, looped.
///
/// Played with the RINGTONE usage on Android, so silent mode and Do Not
/// Disturb are the OS's decision, not this app's. On the web the first play
/// can be refused outright when the session has had no user gesture yet --
/// that refusal is swallowed on purpose: a visible ring without sound beats
/// a crash, and the banner is already on screen.
class AssetRingSound implements RingSound {
  final AudioPlayer _player = AudioPlayer();
  bool _configured = false;

  /// Bumped by every [stop] and every fresh [start], so a [start] that was
  /// superseded WHILE it awaited [_configure] does not go on to play a loop
  /// nobody wants any more -- the stuck-tone race a stop landing inside that
  /// await opens, on the ringback (#8807) and the incoming ring alike.
  int _generation = 0;

  /// Test seam: replaces the platform configure so a test can hold [start]
  /// inside its await and land a [stop] in the gap.
  @visibleForTesting
  Future<void> Function()? configureForTest;

  /// Test seam: set the moment a [start] commits to playing, so a test can
  /// prove a superseded start never reaches it.
  @visibleForTesting
  bool reachedPlayForTest = false;

  /// The looped asset. `phone.ogg` is the incoming ring; a caller's outgoing
  /// ringback loops `call.ogg`.
  final String _loopAsset;

  /// The Android usage the LOOP plays under. An incoming ring is a
  /// notification-ringtone, so silent mode and Do Not Disturb are the OS's
  /// decision. A caller's own ringback is their call's feedback, not a
  /// ringtone, so it plays under the call-signalling usage -- heard even when
  /// ringtones are silenced, the same way the call's voice is.
  final AndroidUsageType _loopUsage;

  AssetRingSound({
    String loopAsset = 'sounds/phone.ogg',
    AndroidUsageType loopUsage = AndroidUsageType.notificationRingtone,
  }) : _loopAsset = loopAsset,
       _loopUsage = loopUsage;

  /// The caller's outgoing ringback: `call.ogg`, looped, under the
  /// call-signalling usage so the caller hears their own call ring out even
  /// with ringtones silenced.
  AssetRingSound.ringback()
    : this(
        loopAsset: 'sounds/call.ogg',
        loopUsage: AndroidUsageType.voiceCommunicationSignalling,
      );

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          usageType: _loopUsage,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
        iOS: AudioContextIOS(),
      ),
    );
  }

  @override
  Future<void> start() async {
    final generation = ++_generation;
    try {
      await (configureForTest ?? _configure)();
      // A stop -- or a newer start -- that landed while we were configuring has
      // moved the generation on; this start is stale and must NOT play a loop
      // the caller no longer wants.
      if (generation != _generation) return;
      reachedPlayForTest = true;
      await _player.play(AssetSource(_loopAsset));
    } catch (e) {
      // Autoplay refused (web without a gesture), or no audio device. The
      // ring is still VISIBLE; sound is the enhancement, not the mechanism.
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
  Future<void> busy() async {
    try {
      await _configure();
      // Twice, briefly: the engaged tone every phone system has trained
      // people to recognise, built from the notification asset this app
      // already ships rather than a new file nobody has heard.
      final beeper = AudioPlayer();
      await beeper.setReleaseMode(ReleaseMode.stop);
      for (var i = 0; i < 2; i++) {
        await beeper.play(AssetSource('sounds/notification.ogg'));
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
      await beeper.dispose();
    } catch (e) {
      // A tone is a courtesy; the words on screen are the message.
      Logs().i('Busy tone not played: $e');
    }
  }
}

/// Rings for exactly as long as one prompt is on screen.
///
/// Keyed by the ring's event id so a stale stop -- a dismissal racing a
/// redial's replacement -- can never silence the NEW call's ring: stop() only
/// acts when the id it names is the one playing. A caller's outgoing ringback
/// (issue #8807) uses this same keyed lifecycle -- keyed on the placing call
/// rather than a ring event, through a [RingSound] built with
/// [AssetRingSound.ringback] so it is the call's own signalling, not a ringtone.
class RingPlayer {
  final RingSound _sound;

  RingPlayer({RingSound? sound}) : _sound = sound ?? AssetRingSound();

  String? _playingFor;

  /// Starts the loop for [ringId]. Playing it again is a no-op; a different
  /// id replaces the loop (stop, then start) so a redial rings afresh.
  void play(String ringId) {
    if (_playingFor == ringId) return;
    final replacing = _playingFor != null;
    _playingFor = ringId;
    unawaited(() async {
      if (replacing) await _sound.stop();
      // Guarded: the prompt may already have gone while the stop settled.
      if (_playingFor == ringId) await _sound.start();
    }());
  }

  /// Stops the loop IF [ringId] is the one ringing. Idempotent; a stale id is
  /// a no-op by design.
  void stop(String ringId) {
    if (_playingFor != ringId) return;
    _playingFor = null;
    unawaited(_sound.stop());
  }

  /// The engaged tone, once. Whatever was ringing stops first: a caller
  /// hearing their own ringback over the busy note learns nothing.
  void busy() {
    stopAll();
    unawaited(_sound.busy());
  }

  /// Stops whatever is ringing. For dispose and account switches.
  void stopAll() {
    if (_playingFor == null) return;
    _playingFor = null;
    unawaited(_sound.stop());
  }

  @visibleForTesting
  String? get playingForTest => _playingFor;
}
