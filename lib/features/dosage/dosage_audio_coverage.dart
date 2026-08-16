import 'package:fluffychat/features/dosage/dosage_audio_category.dart';

/// One coverage declaration: for THIS learner, over THIS period, this build was
/// instrumenting THIS category.
///
/// Without it, "listened to nothing", "app too old to measure" and "signals
/// dropped" are one indistinguishable observation, and the server has no honest
/// way to serve a zero. Coverage records that the instrument was RUNNING, not
/// that it observed something — a covered period with no events is a real zero,
/// which is the entire point.
///
/// Three properties, all load-bearing (D7, carried forward by D-V2-9):
///
///  * **Learner-scoped, not room-scoped.** Instrumentation is a property of the
///    build, not of the room. Scoping it per room would invent an *unknown*
///    wherever the learner was simply in a different room.
///  * **Behaviour-independent.** Declared whether or not any audio occurred.
///  * **Per category.** A build instrumenting two of the three listening
///    categories must not declare coverage for the third, or that category's
///    silence is served as a real zero for every student on it.
///
/// Sent in the SAME batch as that period's audio events so a swallowed write
/// loses both — lose the events, lose the declaration, withhold the counter.
///
/// Design: docs/research/104-speaking-listening-minutes-v2.md, §2b and D-V2-9.
class DosageAudioCoverage {
  /// Client-minted opaque UUIDv4 idempotency key, as for a playback event.
  final String coverageId;

  final DosageCoverageCategory category;

  /// Start of the declared period, UTC, inclusive.
  final DateTime periodStart;

  /// End of the declared period, UTC. Never in the future: a build cannot
  /// declare that it will still be running.
  final DateTime periodEnd;

  const DosageAudioCoverage({
    required this.coverageId,
    required this.category,
    required this.periodStart,
    required this.periodEnd,
  });

  /// Whether the declaration is well-formed enough to send. A zero-length or
  /// inverted period claims nothing and is dropped rather than posted.
  bool get isValid => coverageId.isNotEmpty && periodEnd.isAfter(periodStart);

  Map<String, dynamic> toJson() => {
    "coverage_id": coverageId,
    "category": category.wireName,
    "period_start": periodStart.toUtc().toIso8601String(),
    "period_end": periodEnd.toUtc().toIso8601String(),
  };
}
