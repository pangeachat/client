import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_audio_signals.dart';
import 'package:fluffychat/features/dosage/dosage_playback_meter.dart';

/// Measures one surface's share of the app's SINGLE shared audio player, and
/// emits it as a listening signal of a fixed category.
///
/// The app plays at most one sound at a time through one global `AudioPlayer`,
/// and `voiceMessageEventId` names whichever surface currently holds it. Several
/// surfaces are subscribed to that player at once, so **"the player is playing"
/// is not the same claim as "MY surface is playing"** — and conflating them is
/// how the toolbar's paid read-aloud would be banked as a peer voice message by
/// whatever timeline bubble happened to be mounted. That distinction is the
/// entire reason this class exists, and [ownerId] is what encodes it.
///
/// [category] is a CONSTRUCTION-TIME CONSTANT, never derived from the player
/// state. The shared player cannot tell the categories apart; only the surface
/// that owns the tracker can, and it says so once, here (D-V2-1).
///
/// Pure of Flutter and of `just_audio` so the whole state machine — ownership,
/// pause, completion, double-emit — is testable without a widget or a player.
class DosageSharedPlayerTracker {
  DosageSharedPlayerTracker({
    required this.category,
    required this.roomId,
    required this.ownerId,
    required this.userId,
    required this.accessToken,
    DateTime Function()? now,
    DosageAudioBuffer? buffer,
  }) : _meter = DosagePlaybackMeter(now: now),
       _now = now ?? DateTime.now,
       _buffer = buffer;

  /// What kind of listening a playback through this surface is.
  final DosageListeningCategory category;

  /// The room the playback belongs to. The only identifier that travels.
  final String roomId;

  /// This surface's key in the shared player's owner notifier — the timeline
  /// bubble's event id, the overlay's `_overlay` variant, or the toolbar
  /// button's `_button` variant.
  final String ownerId;

  /// Read LIVE at emit time rather than captured: an account switch or a token
  /// refresh mid-playback must not post under a stale identity.
  final String? Function() userId;
  final String? Function() accessToken;

  final DosagePlaybackMeter _meter;
  final DateTime Function() _now;
  final DosageAudioBuffer? _buffer;

  /// Feeds one player-state transition.
  ///
  /// [currentOwnerId] is the shared player's owner at this instant. When it is
  /// not [ownerId] the playback belongs to somebody else: whatever this surface
  /// had heard up to that point is real and is emitted, and nothing after it is
  /// attributed here.
  void update({
    required bool playing,
    required bool completed,
    required String? currentOwnerId,
  }) {
    if (currentOwnerId != ownerId) {
      close();
      return;
    }
    _meter.setPlaying(playing && !completed);
    if (completed) close();
  }

  /// Closes the measurement and emits it, if anything was heard.
  ///
  /// Synchronous end to end — an in-memory append and nothing more. Idempotent:
  /// [DosagePlaybackMeter.finish] resets, so a completion transition followed by
  /// the surface's `dispose` emits ONCE, not twice.
  void close() {
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
