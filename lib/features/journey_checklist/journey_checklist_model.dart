import 'package:fluffychat/features/journey_checklist/journey_step_enum.dart';

/// The `pangea.journey_checklist` account-data content: when each journey step
/// first happened. Every other field — the app-ask history, or steps from a
/// newer client — is carried through untouched, so a write from this version
/// never erases what a newer one recorded.
class JourneyChecklistModel {
  static const _stepsKey = 'steps';

  /// Step key to when it first happened. Keyed by string, not [JourneyStep],
  /// so steps this version doesn't know survive a write.
  final Map<String, DateTime> steps;

  final Map<String, Object?> _otherFields;

  /// Whether the stored content had a field this version could not read.
  final bool hadMalformedField;

  const JourneyChecklistModel({
    this.steps = const {},
    Map<String, Object?> otherFields = const {},
    this.hadMalformedField = false,
  }) : _otherFields = otherFields;

  factory JourneyChecklistModel.fromJson(Map<String, Object?> json) {
    final steps = <String, DateTime>{};
    var malformed = false;
    final rawSteps = json[_stepsKey];
    if (rawSteps is Map) {
      for (final entry in rawSteps.entries) {
        final at = entry.value;
        if (entry.key is String && at is int) {
          steps[entry.key as String] = DateTime.fromMillisecondsSinceEpoch(at);
        } else {
          malformed = true;
        }
      }
    } else if (rawSteps != null) {
      malformed = true;
    }
    return JourneyChecklistModel(
      steps: steps,
      otherFields: Map.of(json)..remove(_stepsKey),
      hadMalformedField: malformed,
    );
  }

  Map<String, Object?> toJson() => {
    ..._otherFields,
    _stepsKey: steps.map((key, at) => MapEntry(key, at.millisecondsSinceEpoch)),
  };

  bool hasStep(JourneyStep step) => steps.containsKey(step.key);

  /// This checklist with [step] first happening at [at]; an earlier recorded
  /// time is kept.
  JourneyChecklistModel withStep(JourneyStep step, DateTime at) =>
      merge(JourneyChecklistModel(steps: {step.key: at}));

  /// Both checklists' steps, each at its earliest time. Other fields come from
  /// this checklist, with [other]'s filling any this one lacks.
  JourneyChecklistModel merge(JourneyChecklistModel other) {
    final merged = Map.of(steps);
    other.steps.forEach((key, at) {
      final mine = merged[key];
      if (mine == null || at.isBefore(mine)) merged[key] = at;
    });
    return JourneyChecklistModel(
      steps: merged,
      otherFields: {...other._otherFields, ..._otherFields},
      hadMalformedField: hadMalformedField,
    );
  }
}
