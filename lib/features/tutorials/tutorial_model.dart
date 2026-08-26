import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/l10n/l10n.dart';

typedef TutorialSequence = List<TutorialEnum>;

/// One launch of one tutorial: its type, plus the per-step targets and
/// callbacks its host supplied. Copy and geometry come from the type's
/// [TutorialEnum.stepTemplates], so a model can only ever carry exactly as
/// many steps as the tutorial declares.
class TutorialModel {
  final TutorialEnum tutorialType;
  final List<TutorialStepData> _stepsData;

  TutorialModel({
    required this.tutorialType,
    required List<TutorialStepData> stepsData,
  }) : assert(
         stepsData.length == tutorialType.stepCount,
         "$tutorialType declares ${tutorialType.stepCount} steps but was given ${stepsData.length}",
       ),
       _stepsData = stepsData;

  TutorialStep step(int index, L10n l10n) => TutorialStep(
    data: _stepsData[index],
    style: tutorialType.stepTemplates[index].resolve(
      l10n,
      _stepsData[index].resolvedTooltipArgs,
    ),
    type: tutorialType,
    index: index,
  );

  /// The step's raw data, without allocating styles or requiring an [L10n].
  /// Safe to call every frame.
  TutorialStepData dataAt(int index) => _stepsData[index];
}
