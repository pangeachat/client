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
  /// Client-minted opaque UUIDv4, FRESH PER DECLARATION — never reused across the
  /// seals that extend one period.
  ///
  /// Unlike a playback's id this is not an idempotency key, and the difference is
  /// the point. A playback is banked by `(sender, playback_id)`, so a retry of the
  /// same id is a no-op. A coverage row is banked by the natural key
  /// `(sender, category, period_start)` under an extend-only upsert: the server
  /// accepts this field and deliberately does not store it, because keying on it
  /// would bank a second row for a period the client meant to LENGTHEN — which is
  /// exactly the row explosion the extend-only key exists to prevent.
  ///
  /// So it stays per declaration rather than becoming per period. It carries no
  /// wire meaning to make stable, a stable one would suggest a deduplication the
  /// server does not perform, and one seal can legitimately emit several
  /// declarations for the same category when a period is cut at a UTC midnight —
  /// two distinct rows that a shared id would misrepresent as one.
  final String coverageId;

  final DosageCoverageCategory category;

  /// Start of the declared period, UTC, inclusive. NOT necessarily where the
  /// declaring flush began observing: a seal whose interval abuts a period the
  /// ingest has already acknowledged re-declares that period's start so the
  /// upsert extends one row. What the declaration ADDS is still only the interval
  /// its own flush observed.
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
