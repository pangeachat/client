/// One dosage engagement span: a contiguous window of foreground learner
/// activity, timestamps only (no content). The wire body is the verbatim
/// [toJson] under `spans[]`; the BFF ingest is `extra="forbid"`, so this carries
/// EXACTLY the five contract keys and no `sender` (bound server-side).
///
/// Minutes are computed server-side as the interval UNION per sender across all
/// spans/devices, so overlaps and retries can never double-count — the client
/// only reports honest start/end windows.
class DosageEngagementSpan {
  /// Server caps a span at 30 minutes (the `dosage_engagement_spans` CHECK).
  /// The client flushes at heartbeat cadence, so real spans are far shorter;
  /// the cap is the abuse ceiling and the tracker rolls a span over before it.
  static const Duration maxSpan = Duration(minutes: 30);

  final String deviceId;
  final String spanId;
  final DateTime spanStart;
  final DateTime spanEnd;
  final String platform;

  const DosageEngagementSpan({
    required this.deviceId,
    required this.spanId,
    required this.spanStart,
    required this.spanEnd,
    required this.platform,
  });

  Map<String, dynamic> toJson() => {
    "device_id": deviceId,
    "span_id": spanId,
    "span_start": spanStart.toUtc().toIso8601String(),
    "span_end": spanEnd.toUtc().toIso8601String(),
    "platform": platform,
  };
}
