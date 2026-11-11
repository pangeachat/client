import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:fluffychat/features/dosage/dosage_voice_message.dart';

/// One finished call: how long this learner was connected with the other person.
///
/// Calls have no speaking signal of their own: nothing here separates who spoke,
/// so this reports connected time, the figure the call card shows, and the server
/// stores it as call time beside voice messages in speaking minutes.
///
/// The wire body is the verbatim [toJson] under `calls[]`. The ingest is
/// `extra="forbid"` and binds identity from the bearer token, so this carries
/// exactly the four contract keys and no `sender`.
class DosageCallTime {
  /// The server's ceiling on one signal, shared with voice messages. A longer
  /// figure would 422 the batch it rides in, so it is dropped, never clamped.
  static const int maxConnectedMs = DosageVoiceMessage.maxDurationMs;

  /// Stable for one device's stay in one call, so a retried batch, or the same
  /// call reported twice, is one row. See [idFor].
  final String callId;

  /// The direct chat the call happened in.
  final String roomId;

  /// The learner's own connected time, in milliseconds.
  final int connectedMs;

  /// When the call ended here, UTC.
  final DateTime ts;

  const DosageCallTime({
    required this.callId,
    required this.roomId,
    required this.connectedMs,
    required this.ts,
  });

  /// One id per (room, call, device, join). Two devices in one call each report
  /// their own stretch, and so does a rejoin, so none replaces another. The call
  /// key can be null, for a call that never resolved one; the join instant still
  /// tells it apart. Hashed over a JSON list, which frames each field, so no two
  /// sets of fields can run together into one id.
  static String idFor({
    required String roomId,
    required String? callKey,
    required String? deviceId,
    required DateTime talkStartedAt,
  }) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            roomId,
            callKey,
            deviceId,
            talkStartedAt.toUtc().millisecondsSinceEpoch,
          ]),
        ),
      )
      .toString();

  /// Mirrors the server's `_CallItem`, so a row that would 422 its whole batch is
  /// dropped here first.
  bool get isValid =>
      callId.isNotEmpty &&
      roomId.isNotEmpty &&
      connectedMs > 0 &&
      connectedMs <= maxConnectedMs;

  Map<String, dynamic> toJson() => {
    "call_id": callId,
    "room_id": roomId,
    "connected_ms": connectedMs,
    "ts": ts.toUtc().toIso8601String(),
  };
}
