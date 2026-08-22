import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' show Logs;

/// The looping sound itself, behind a seam so the keyed lifecycle can be
/// tested without a platform audio plugin.
abstract class RingSound {
  Future<void> start();
  Future<void> stop();
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

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.notificationRingtone,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
        iOS: AudioContextIOS(),
      ),
    );
  }

  @override
  Future<void> start() async {
    try {
      await _configure();
      await _player.play(AssetSource('sounds/phone.ogg'));
    } catch (e) {
      // Autoplay refused (web without a gesture), or no audio device. The
      // ring is still VISIBLE; sound is the enhancement, not the mechanism.
      Logs().i('Ring sound not played: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}

/// Rings for exactly as long as one prompt is on screen.
///
/// Keyed by the ring's event id so a stale stop -- a dismissal racing a
/// redial's replacement -- can never silence the NEW call's ring: stop() only
/// acts when the id it names is the one playing. There is deliberately no
/// outgoing ringback; the ecosystem does not play one and neither does this.
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

  /// Stops whatever is ringing. For dispose and account switches.
  void stopAll() {
    if (_playingFor == null) return;
    _playingFor = null;
    unawaited(_sound.stop());
  }

  @visibleForTesting
  String? get playingForTest => _playingFor;
}
