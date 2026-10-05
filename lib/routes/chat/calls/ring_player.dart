import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:matrix/matrix.dart' show Logs;

/// A minimal seam over audioplayers' [AudioPlayer], so the ring lifecycle --
/// configure, play, stop, playback-completion, dispose -- can be driven in a
/// unit test without a platform audio plugin. The default is a thin wrapper
/// over a real [AudioPlayer]; [AssetRingSound] builds one for the loop and one
/// per one-shot cue.
abstract class RingAudio {
  /// Prepare the player: [loop] chooses the release mode, [context] the
  /// Android/iOS audio context.
  Future<void> configure({required bool loop, required AudioContext context});

  /// Start playing [asset]. Resolves when playback STARTS, not when it ends.
  Future<void> play(String asset);

  Future<void> stop();
  Future<void> pause();

  /// Completes when the current playback finishes. One-shot teardown waits on
  /// this rather than a fixed timer, so a cue is never cut off part-way.
  Future<void> get complete;

  Future<void> dispose();
}

/// The real [RingAudio]: a thin wrapper over one audioplayers [AudioPlayer].
class _AudioPlayersRing implements RingAudio {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> configure({
    required bool loop,
    required AudioContext context,
  }) async {
    await _player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
    await _player.setAudioContext(context);
  }

  @override
  Future<void> play(String asset) => _player.play(AssetSource(asset));

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> get complete => _player.onPlayerComplete.first;

  @override
  Future<void> dispose() => _player.dispose();
}

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

  /// Release every native player this sound owns. The sound must not be used
  /// after this. Idempotent and best-effort: teardown never throws.
  Future<void> dispose();
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
  /// The longest a one-shot cue waits for its completion event before tearing
  /// its player down anyway -- a safety bound, not the expected path, so a
  /// completion that never arrives cannot wedge the cue for ever.
  static const Duration _oneShotMaxWait = Duration(seconds: 8);

  /// Builds a fresh [RingAudio]. The persistent loop player and every throwaway
  /// one-shot player come from here, so a test can substitute a fake.
  final RingAudio Function() _audioFactory;

  late final RingAudio _player = _audioFactory();
  bool _configured = false;

  /// The in-flight [_configure], so concurrent [start]s share the ONE
  /// configuration instead of each racing a partial one; cleared when it
  /// settles so a configuration that FAILED is retried, not cached as done.
  Future<void>? _configuring;

  /// Bumped synchronously by every [start], [stop] and [dispose] as it is
  /// CALLED. A queued [start] whose captured generation no longer matches when
  /// its turn comes was overtaken by a later call, so it does nothing -- it
  /// neither configures nor plays, and cannot leave a loop nobody wants.
  int _generation = 0;

  /// Serializes every operation that touches the shared loop [_player] -- start,
  /// stop, dispose -- so they never run concurrently. This is what makes a
  /// stale start safe: it simply skips its turn, and no cancel has to race a
  /// newer play. One-shot cues run on their OWN players and are NOT on this
  /// chain.
  Future<void> _loopOps = Future<void>.value();

  /// True once disposed; no new cue starts after it.
  bool _disposed = false;

  /// The one-shot cues still playing, so [dispose] can wait for each to finish
  /// and tear its own player down rather than leaving one behind.
  final Set<Future<void>> _oneShots = {};

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
    @visibleForTesting RingAudio Function()? audioFactory,
  }) : _usage = usage,
       _audioFactory = audioFactory ?? (() => _AudioPlayersRing());

  /// A caller's own call cues (#8807), played under the call-signalling usage so
  /// the caller hears them even with ringtones silenced.
  AssetRingSound.callSignalling({
    @visibleForTesting RingAudio Function()? audioFactory,
  }) : this(
         usage: AndroidUsageType.voiceCommunicationSignalling,
         audioFactory: audioFactory,
       );

  AudioContext _context() => AudioContext(
    android: AudioContextAndroid(
      usageType: _usage,
      contentType: AndroidContentType.sonification,
      audioFocus: AndroidAudioFocus.gainTransient,
    ),
    iOS: AudioContextIOS(),
  );

  /// Configure the loop player exactly once. [_configured] flips true only
  /// AFTER the platform calls complete, so a start that runs while configure is
  /// still in flight waits for the SAME future instead of playing half-set-up;
  /// a configure that throws clears the in-flight future so the next start
  /// retries it rather than inheriting an unconfigured player.
  Future<void> _configure() {
    if (_configured) return Future<void>.value();
    return _configuring ??= () async {
      try {
        await _player.configure(loop: true, context: _context());
        _configured = true;
      } finally {
        _configuring = null;
      }
    }();
  }

  /// Runs [op] after every loop operation queued before it, so start/stop/
  /// dispose never touch the shared [_player] concurrently. Returns the future
  /// for THIS op (so a caller can await just its own work); the chain keeps
  /// going even if an op throws, without swallowing the failure silently.
  Future<void> _enqueueLoop(Future<void> Function() op) {
    final result = _loopOps.then((_) => op());
    _loopOps = result.catchError(
      (Object e) => Logs().w('Ring loop operation failed: $e'),
    );
    return result;
  }

  @override
  Future<void> start(String asset) {
    if (_disposed) return Future<void>.value();
    // The generation moves NOW, as this start is requested, so any start
    // already queued is marked stale the instant this one supersedes it.
    final generation = ++_generation;
    return _enqueueLoop(() async {
      // Overtaken before (or while) our turn came up -- a later stop, start or
      // dispose moved the generation on. A stale start does nothing: it neither
      // configures nor plays, so it cannot leave a loop nobody wants.
      if (_disposed || generation != _generation) return;
      try {
        await _configure();
        // A stop/start/dispose that landed WHILE we configured supersedes us
        // too; re-check before committing the player to a loop.
        if (generation != _generation) return;
        reachedPlayForTest = true;
        await _player.play(asset);
      } catch (e) {
        // Autoplay refused (web without a gesture), or no audio device. The cue
        // is an enhancement, not the mechanism.
        Logs().i('Ring sound not played: $e');
      }
    });
  }

  @override
  Future<void> stop() {
    // Abandon once disposed: after dispose the loop player is released, so a
    // stop that reached it would call stop()/pause() on a dead player -- a
    // use-after-dispose. The SAME rule [start] and the one-shots already
    // follow; stop is the one operation that touches the shared player and had
    // been missing it.
    if (_disposed) return Future<void>.value();
    // Supersede any start not yet played, then stop -- serialized behind any
    // in-flight loop op, so the stop never races a play on the shared player.
    _generation++;
    return _enqueueLoop(_stopPlayer);
  }

  /// Stop the loop player, surfacing a failure -- a stop that leaves the loop
  /// audible while ownership is already cleared is NOT benign -- and attempting
  /// a best-effort pause so the caller is not stuck under a tone nothing can
  /// silence. Shared by [stop] and [dispose] so neither swallows a failed stop.
  Future<void> _stopPlayer() async {
    try {
      await _player.stop();
    } catch (e) {
      Logs().w('Ring sound failed to stop: $e');
      try {
        await _player.pause();
      } catch (_) {
        // silent-ok: the stop failure above is already logged; a failed pause
        // recovery adds nothing further actionable.
      }
    }
  }

  @override
  Future<void> busy() =>
      _oneShot('sounds/notification.ogg', times: 2, gapMs: 450);

  @override
  Future<void> playOnce(String asset) => _oneShot(asset, times: 1);

  /// Plays [asset] [times] on a THROWAWAY player, so a one-shot cue never
  /// touches -- or gets stopped alongside -- the looping player. Tracked so
  /// [dispose] can wait for it to finish.
  Future<void> _oneShot(String asset, {required int times, int gapMs = 0}) {
    if (_disposed) return Future<void>.value();
    final future = _runOneShot(asset, times: times, gapMs: gapMs);
    _oneShots.add(future);
    // [_runOneShot] catches everything and never completes with an error, so
    // this cleanup future cannot reject; unawaited() documents the deliberate
    // fire-and-forget and keeps a stray rejection from going unhandled.
    unawaited(future.whenComplete(() => _oneShots.remove(future)));
    return future;
  }

  Future<void> _runOneShot(
    String asset, {
    required int times,
    required int gapMs,
  }) async {
    // Built INSIDE the try so a factory that throws is caught and logged here
    // rather than escaping as an unhandled error on the untracked cleanup path.
    RingAudio? beeper;
    try {
      beeper = _audioFactory();
      await beeper.configure(loop: false, context: _context());
      for (var i = 0; i < times; i++) {
        if (i > 0) {
          await Future<void>.delayed(Duration(milliseconds: gapMs));
        }
        await beeper.play(asset);
        // Wait for THIS note to finish before the next one -- or the teardown --
        // so a cue longer than any fixed guess is never cut off. Bounded, so a
        // completion event that never arrives cannot wedge the cue for ever;
        // that bound is surfaced, not swallowed.
        await beeper.complete.timeout(
          _oneShotMaxWait,
          onTimeout: () => Logs().i(
            'Call cue completion not signalled within '
            '${_oneShotMaxWait.inSeconds}s; tearing it down',
          ),
        );
      }
    } catch (e) {
      // A cue is a courtesy; the words on screen are the message.
      Logs().i('Call cue not played: $e');
    } finally {
      // Dispose on EVERY path -- a configure or play that threw reaches here
      // too, so no throwaway player leaks on the error path.
      try {
        await beeper?.dispose();
      } catch (e) {
        Logs().w('Call cue player failed to dispose: $e');
      }
    }
  }

  /// The in-flight teardown. A second [dispose] returns the SAME future, so a
  /// concurrent caller AWAITS the first teardown (and the one-shots it drains)
  /// rather than getting an early-resolved future -- an awaited dispose means
  /// teardown is done for every caller, not only the first.
  Future<void>? _disposal;

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    // Supersede any start not yet played so it stays silent.
    _generation++;
    // Stop then release the loop player SERIALIZED behind any in-flight start/
    // stop, so the player is never disposed out from under an op still running.
    await _enqueueLoop(() async {
      await _stopPlayer();
      try {
        await _player.dispose();
      } catch (e) {
        Logs().w('Ring sound failed to dispose: $e');
      }
    });
    // Let any one-shot still playing (its own player) finish and tear itself
    // down, so teardown leaves no player behind.
    for (final oneShot in _oneShots.toList()) {
      try {
        await oneShot;
      } catch (_) {
        // silent-ok: _runOneShot logs its own failures; here we only wait.
      }
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
///
/// Every mutating call runs on one serialized chain, so a stop always finishes
/// before the play that follows it: cues never overlap, and a superseding cue
/// never races the one it replaces on the shared player.
class RingPlayer {
  final RingSound _sound;

  RingPlayer({RingSound? sound}) : _sound = sound ?? AssetRingSound();

  String? _playingFor;
  bool _disposed = false;

  /// The tail of the operation chain. Each new op runs strictly after the one
  /// before it, which is what keeps a stop ahead of the next play.
  Future<void> _operations = Future<void>.value();

  void _enqueue(Future<void> Function() op) {
    _operations = _operations
        .then((_) => op())
        .catchError((Object e) => Logs().w('Ring cue operation failed: $e'));
  }

  /// Loops [asset] for [ringId]. The same id is a no-op; a different id replaces
  /// the loop (stop, then start) so a redial -- or a switch to another cue --
  /// plays afresh.
  void play(String ringId, {required String asset}) {
    if (_disposed || _playingFor == ringId) return;
    final replacing = _playingFor != null;
    _playingFor = ringId;
    _enqueue(() async {
      if (replacing) await _sound.stop();
      // Guarded: the cue may already have gone while the stop settled.
      if (_playingFor == ringId) await _sound.start(asset);
    });
  }

  /// Stops the loop IF [ringId] is the one playing. Idempotent; a stale id is a
  /// no-op by design.
  void stop(String ringId) {
    // No mutator acts after dispose -- the same rule [play], [busy] and [once]
    // follow -- so a stop can never enqueue an op on the released sound.
    if (_disposed) return;
    if (_playingFor != ringId) return;
    _playingFor = null;
    _enqueue(_sound.stop);
  }

  /// The engaged tone, once. Whatever was looping stops first -- and, being on
  /// the one chain, has fully stopped BEFORE the tone plays: a caller hearing
  /// their own ringback over the busy note learns nothing.
  void busy() {
    if (_disposed) return;
    stopAll();
    _enqueue(_sound.busy);
  }

  /// A one-shot cue -- the call-cut tone (#8807) -- once. Plays on a throwaway
  /// player, so it does NOT stop the loop; the caller stops the loop through
  /// [stop]/[stopAll] as the call resolves, and this only says "it ended". It
  /// still runs after any pending stop on the chain, so it cannot overlap one.
  void once(String asset) {
    if (_disposed) return;
    _enqueue(() => _sound.playOnce(asset));
  }

  /// Stops whatever is looping. For cue transitions and account switches.
  void stopAll() {
    // No mutator acts after dispose (see [stop]); teardown releases the sound.
    if (_disposed) return;
    if (_playingFor == null) return;
    _playingFor = null;
    _enqueue(_sound.stop);
  }

  /// The in-flight teardown, so a concurrent second [dispose] returns the SAME
  /// future and AWAITS this teardown rather than resolving early -- an awaited
  /// dispose means the operation chain has drained for every caller.
  Future<void>? _disposal;

  /// Stops whatever is playing and releases the native player, in that order.
  /// After this the player must not be used again. For session/account
  /// teardown, so no call leaves an AudioPlayer behind.
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _playingFor = null;
    _enqueue(_sound.stop);
    _enqueue(_sound.dispose);
    await _operations;
  }

  @visibleForTesting
  String? get playingForTest => _playingFor;
}
