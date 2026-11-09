import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';

/// Stands in for the learner's profile: every tutorial unseen unless named in
/// [seen], resuming at whatever [resumeSteps] says.
class FakeTutorialProgress extends TutorialProgressSource {
  final Set<TutorialEnum> seen;
  final Map<TutorialEnum, int> resumeSteps;

  /// Records what the controller persisted, when observing writes matters.
  /// A tutorial saved at its step count was marked seen.
  final Map<TutorialEnum, int>? progressLog;

  const FakeTutorialProgress({
    this.seen = const {},
    this.resumeSteps = const {},
    this.progressLog,
  });

  @override
  bool isEnabled(TutorialEnum tutorial) => !seen.contains(tutorial);

  @override
  int resumeStep(TutorialEnum tutorial) => resumeSteps[tutorial] ?? 0;

  @override
  void saveProgress(TutorialEnum tutorial, int stepIndex) =>
      progressLog?[tutorial] = stepIndex;
}
