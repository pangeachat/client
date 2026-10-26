import 'package:fluffychat/features/journey_checklist/journey_moments.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';

class FreeTrialOnboardingStep extends OnboardingStep {
  const FreeTrialOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  @override
  bool get customView => true;

  @override
  Future<OnboardingStep?> execute() async {
    JourneyMoments.trialPageClosed(client);
    try {
      await state.trialInfoProvider.setShowedTrialPage();
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
    }

    return null;
  }

  @override
  OnboardingStep? skip() {
    throw StateError("Cannot skip free trial onboarding step");
  }
}
