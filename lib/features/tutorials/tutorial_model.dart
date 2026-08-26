import 'package:fluffychat/features/tutorials/tutorial_copy.dart';
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

  /// The greeting, which is the same on both surfaces that can fire it — the
  /// world map and a course plan, whichever the learner reaches first. Defined
  /// once here rather than in each host because, alone among the steps, it
  /// prepares no host UI state: it needs only the greeting itself.
  ///
  /// The copy's `{greeting}` placeholder takes [TutorialCopy.wordSlot] when the
  /// word can be a bubble, so the tooltip knows where to put it, and the plain
  /// word when it cannot.
  factory TutorialModel.welcome(TutorialGreeting greeting) => TutorialModel(
    tutorialType: TutorialEnum.welcome,
    stepsData: [
      // No target: the greeting is about the app, not about anything on screen,
      // so it centers over the darkened surface.
      TutorialStepData(
        canShowNextStep: () => true,
        tooltipArgs: () => [
          greeting.isBubble ? TutorialCopy.wordSlot : greeting.word,
        ],
        wordBubble: () => greeting,
      ),
    ],
  );

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
