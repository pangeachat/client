import 'package:fluffychat/features/dosage/dosage_audio_category.dart';

/// One audio-playback signal: the learner listened to something, in this room,
/// for this long. Content-free and — deliberately — source-free.
///
/// **The minimisation rule is enforced HERE, at the point of collection.** The
/// produced direction (a sent voice message) may carry the learner's own event
/// id; the CONSUMED direction carries **no source event id and no source
/// sender**. Categories 1 and 3 both play a specific message and their call
/// sites are handed the room, the event and the sender — the identifying data
/// is in hand at the moment this object is built, and it is dropped here rather
/// than filtered downstream. Collecting it would build a per-student record of
/// which peers a learner attends to: a social-graph fact about a third party
/// that no counter consumes.
///
/// The wire body is the verbatim [toJson] under `events[]`. The BFF ingest is
/// `extra="forbid"` and binds identity from the bearer token, so this carries
/// EXACTLY the five contract keys and no `sender`.
///
/// Design: docs/research/104-speaking-listening-minutes-v2.md, §7.
class DosageAudioEvent {
  /// Abuse ceiling on a single playback, mirroring the shape of the engagement
  /// span's server-side CHECK. Four hours is far past any real message playback;
  /// a wall clock that somehow ran longer is a bug or a suspended device, and a
  /// capped number is better than a 422 that rejects the whole batch.
  static const int maxElapsedMs = 4 * 60 * 60 * 1000;

  /// Client-minted opaque UUIDv4. This is the idempotency key: the ingest table
  /// is `PRIMARY KEY (sender_mxid, playback_id)` with `ON CONFLICT DO NOTHING`,
  /// which is what makes the retry buffer safe by construction. It is NOT a
  /// Matrix event id and must never be derived from one.
  final String playbackId;

  /// The room the playback happened in. Required: without a room the signal
  /// cannot be bucketed to a course at all — the exact defect `activeMinutes`
  /// already demonstrates.
  final String roomId;

  final DosageListeningCategory category;

  /// Elapsed playback WALL CLOCK, not the asset's duration. Accumulated only
  /// while the player reports playing, so a pause does not bank time and a
  /// stopped playback reports what was actually heard.
  final int elapsedMs;

  /// When the playback ENDED, UTC.
  final DateTime ts;

  const DosageAudioEvent({
    required this.playbackId,
    required this.roomId,
    required this.category,
    required this.elapsedMs,
    required this.ts,
  });

  /// Builds a signal from a finished playback, clamping the magnitude to the
  /// server ceiling. No threshold and no floor is applied: the client emits raw
  /// elapsed time, and any magnitude floor lives on the server as a named
  /// constant where it changes in a day rather than behind an app-store cycle
  /// (D-V2-2).
  factory DosageAudioEvent.fromPlayback({
    required String playbackId,
    required String roomId,
    required DosageListeningCategory category,
    required Duration elapsed,
    required DateTime endedAt,
  }) => DosageAudioEvent(
    playbackId: playbackId,
    roomId: roomId,
    category: category,
    elapsedMs: elapsed.inMilliseconds.clamp(0, maxElapsedMs),
    ts: endedAt.toUtc(),
  );

  Map<String, dynamic> toJson() => {
    "playback_id": playbackId,
    "room_id": roomId,
    "category": category.wireName,
    "elapsed_ms": elapsedMs,
    "ts": ts.toUtc().toIso8601String(),
  };
}
