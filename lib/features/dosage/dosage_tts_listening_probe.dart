import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_audio_signals.dart';
import 'package:fluffychat/features/dosage/dosage_playback_meter.dart';

/// Measures one `TtsController.tryToSpeak` call and emits it as a listening
/// signal of a fixed category.
///
/// The text-to-speech counterpart of `DosageSharedPlayerTracker`, and it exists
/// for the same reason: **one entry point serves several kinds of listening**.
/// `tryToSpeak` reads arriving messages aloud, reads a message the toolbar was
/// opened on, and plays word and choice taps, and it takes neither a room nor an
/// event id — it could not name a category if it wanted to. So [category] is a
/// CONSTRUCTION-TIME CONSTANT supplied by the caller (D-V2-1), and the two
/// read-aloud call sites differ in exactly that one argument.
///
/// **Why the returned future is not enough to measure with.** Several exits from
/// `tryToSpeak` resolve having played nothing — the tool setting is off, the
/// request was superseded, or `allowChoreoPlay: false` met a device with no
/// known-good voice, which returns near instantly. Timing the call would bank a
/// near-zero interval for audio nobody heard. [started] is wired to
/// `onPlaybackStarted`, which fires only when a route is actually asked to play,
/// and [aborted] to `onPlaybackAborted`, which fires when a route that was asked
/// did not play. Between them they bracket real audio and nothing else.
///
/// Synchronous end to end. [finish] appends to an in-memory buffer and returns;
/// nothing here is awaited and no user action waits on it.
class DosageTtsListeningProbe {
  DosageTtsListeningProbe({
    required this.category,
    required this.roomId,
    required this.userId,
    required this.accessToken,
    DateTime Function()? now,
    DosageAudioBuffer? buffer,
  }) : _meter = DosagePlaybackMeter(now: now),
       _now = now ?? DateTime.now,
       _buffer = buffer;

  /// What kind of listening a playback through this call is. Named once, by the
  /// caller, and never derived from the request or its route.
  final DosageListeningCategory category;

  /// The room the playback belongs to. The only identifier that travels.
  final String roomId;

  /// Read LIVE at emit time rather than captured: an account switch or a token
  /// refresh mid-playback must not post under a stale identity.
  final String? Function() userId;
  final String? Function() accessToken;

  final DosagePlaybackMeter _meter;
  final DateTime Function() _now;
  final DosageAudioBuffer? _buffer;

  /// A route is about to play. Opens the interval.
  void started() => _meter.setPlaying(true);

  /// A route that was asked to play did not. Drops the interval it opened,
  /// BEFORE any fallback route opens its own — otherwise the time spent failing,
  /// and the time spent switching routes, is banked as audio the learner heard.
  void aborted() => _meter.discardRunningInterval();

  /// Closes the measurement and emits it, if anything was heard.
  ///
  /// Idempotent: [DosagePlaybackMeter.finish] resets, so a second call emits
  /// nothing. Call it in a `finally` so a throw out of TTS still closes the
  /// measurement, and after the await so nothing here can delay speech.
  void finish() {
    final elapsed = _meter.finish();
    if (elapsed == null) return;
    DosageAudioSignals.recordPlayback(
      category: category,
      roomId: roomId,
      elapsed: elapsed,
      userId: userId(),
      accessToken: accessToken(),
      endedAt: _now(),
      buffer: _buffer,
    );
  }
}
