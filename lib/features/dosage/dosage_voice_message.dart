/// One learner voice message the client reports, WITH its own duration.
///
/// The client-reported half of speaking (admin-dash-api#150 / #104). Speaking's
/// magnitude is `content.info.duration`, which the sender's client holds at send
/// time — and for a DM / 1:1 / bot room it is the ONLY place that duration ever
/// exists: nothing enumerates a room's timeline, and a TEACHER's token (the
/// server's only other populate path) cannot read a learner's 1:1 `m.audio`. So
/// unless the sender's own client reports it, `dosage_voice_messages` stays empty
/// and speaking is withheld.
///
/// **This is the one place the listening lane's minimisation rule does not
/// apply, and that is the point rather than an exception to it.** A playback
/// carries no source event id (see [DosageAudioEvent]); this DOES carry one — but
/// [msgId] is the learner's OWN `m.audio` event, names no third party, and IS the
/// key the speaking projection is written under. It is the SAME id the message's
/// `pvm` construct uses carry, so the server's completeness check correlates the
/// two on `(sender_mxid, msg_id)` and its idempotent `ON CONFLICT DO NOTHING`
/// dedups a retry against the Matrix-resolved path — no double count.
///
/// The wire body is the verbatim [toJson] under `voice_messages[]`. The BFF
/// ingest is `extra="forbid"` and binds identity from the bearer token, so this
/// carries EXACTLY the four contract keys and NO `sender`.
///
/// Design: docs/research/104-speaking-listening-minutes-v2.md.
class DosageVoiceMessage {
  /// Abuse ceiling on a single voice message, mirroring the server's
  /// `MAX_PLAYBACK_MS` (4h) exactly. The server's router rejects a
  /// `duration_ms` outside `[0, MAX_PLAYBACK_MS]` with a 422 that takes the
  /// sibling playback + coverage lanes in the same body down with it, so an
  /// over-bound value must be DROPPED here, never sent and never clamped:
  /// clamping would bank a fabricated 4h magnitude, and dropping leaves the
  /// message unresolved so the server withholds rather than invents (the same
  /// fail-closed rule the server applies to its own over-bound input).
  static const int maxDurationMs = 4 * 60 * 60 * 1000;

  /// The learner's OWN `m.audio` Matrix event id — the resolved, server-assigned
  /// id (`$...`), never a local transaction id. Required and non-empty: it is the
  /// primary key the row is written under and the exact id the `pvm` completeness
  /// check correlates on, so a blank one could never clear the counter it is
  /// meant to measure. Reusing the id the send resolved to is what makes a retry
  /// dedup against both the sibling client rows and the Matrix-resolved path.
  final String msgId;

  /// The room the voice message was sent to. Required and non-empty — a sent
  /// voice message is addressed to one room's participants, so its room is
  /// constitutive of the act and the projection stores it NOT NULL. Unlike a
  /// roomless playback there is no legitimate null here.
  final String roomId;

  /// `content.info.duration` as the client measured it, in milliseconds — the
  /// same field and unit the Matrix-resolved path banks. Bounded to
  /// [maxDurationMs]; see [isValid].
  final int durationMs;

  /// When the voice message was SENT, UTC. Serialised tz-aware (`Z`) for the
  /// server's `AwareDatetime`; kept honest (send time, i.e. slightly in the
  /// past by post time) so the ingest horizon + future-skew gates accept it.
  final DateTime ts;

  const DosageVoiceMessage({
    required this.msgId,
    required this.roomId,
    required this.durationMs,
    required this.ts,
  });

  /// Whether this row is well-formed enough to send. Mirrors the server's own
  /// `_VoiceMessageItem` constraints EXACTLY so a value that would 422 the whole
  /// batch on the server is dropped here first: a non-empty msg id and room id,
  /// and a duration inside `[0, maxDurationMs]`. An out-of-range duration is a
  /// client clock bug and is dropped, not clamped.
  bool get isValid =>
      msgId.trim().isNotEmpty &&
      roomId.isNotEmpty &&
      durationMs >= 0 &&
      durationMs <= maxDurationMs;

  Map<String, dynamic> toJson() => {
    "msg_id": msgId,
    "room_id": roomId,
    "duration_ms": durationMs,
    "ts": ts.toUtc().toIso8601String(),
  };
}
