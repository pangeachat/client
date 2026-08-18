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

  /// The room the playback happened in, or null when the surface has none.
  ///
  /// **Null is a legitimate value and the empty string is not.** Six of the ten
  /// read-aloud surfaces play outside any room at all — the vocab list is a
  /// cross-room aggregate, analytics practice has no room, the activity start
  /// page has none until a session room exists — and inventing one would put a
  /// room's worth of fabricated listening into a table the serving side buckets
  /// and authorizes on. So a roomless playback says so, and the serving side
  /// answers it honestly: it lands in the whole-language width, whose room
  /// conjunct is absent, and is excluded from the course width, where a zero
  /// truthfully means "none attributable to this course".
  ///
  /// An EMPTY string is neither of those things. It is a room that was supposed
  /// to arrive and did not — a bug at the call site wearing a roomless
  /// surface's clothes — and it is dropped rather than sent. See
  /// [hasWellFormedRoom].
  final String? roomId;

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
    required String? roomId,
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

  /// Whether [roomId] is something the wire can carry.
  ///
  /// The rule lives here rather than at each guard so the two places that drop
  /// a malformed event — the buffer on the way in, the repo on the way out —
  /// cannot drift apart on what "malformed" means. Null passes: it says the
  /// surface has no room. The empty string does not: it says a room was meant
  /// to be here.
  bool get hasWellFormedRoom => roomId == null || roomId!.isNotEmpty;

  /// The key set is the CONTRACT: the ingest model is `extra="forbid"` and it
  /// distinguishes an ABSENT `room_id` from a null one. So a roomless playback
  /// sends the key with a null value rather than dropping it — omitting it
  /// would be a different statement to a server that reads the difference.
  Map<String, dynamic> toJson() => {
    "playback_id": playbackId,
    "room_id": roomId,
    "category": category.wireName,
    "elapsed_ms": elapsedMs,
    "ts": ts.toUtc().toIso8601String(),
  };
}
