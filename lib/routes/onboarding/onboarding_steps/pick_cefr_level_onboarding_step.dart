import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/custom_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/free_trial_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

class PickCefrLevelOnboardingStep extends OnboardingStep {
  PickCefrLevelOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  @override
  bool get enableGoForward => state.languageLevel != null;

  void selectCefrLevel(LanguageLevelTypeEnum? level) =>
      state.setLanguageLevel(level);

  @override
  Future<OnboardingStep?> execute() async {
    final level = state.languageLevel;
    final type = state.userType;

    if (level == null || type == null) {
      throw StateError("Pick cefr level step is not fully set up");
    }

    // A failed save doesn't stop onboarding: an unfinished run resumes on this
    // page, so stopping here could keep the person out of the app on every
    // open (onboarding.instructions.md § What onboarding reads and saves).
    try {
      await state.accountUpdater.updateProfile((profile) {
        return profile.copyWith(
          userSettings: profile.userSettings.copyWith(cefrLevel: level),
        );
      });
      await markLevelSaved();
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'level': level.string});
    }

    return nextStep(type);
  }

  /// The page after this one, or null when onboarding ends here. A resumed run
  /// asks too, to open past a level that is already saved.
  OnboardingStep? nextStep(UserType type) {
    // A joined course ends onboarding on the joined-course page, and for a
    // teacher it takes the place of the course request — they already have a
    // course. See onboarding.instructions.md.
    if (state.joinedRoomId != null) {
      return JoinedCourseOnboardingStep.next(client: client, state: state);
    }

    return switch (type) {
      UserType.student =>
        state.trialInfoProvider.shouldShowTrialPage
            ? FreeTrialOnboardingStep(
                client: client,
                state: state,
                maxRemainingSteps: maxRemainingSteps,
              )
            : null,
      // The trial page can follow, so the request's button says Next then.
      UserType.teacher => CustomCourseOnboardingStep(
        client: client,
        state: state,
        maxRemainingSteps: state.trialInfoProvider.shouldShowTrialPage ? 1 : 0,
      ),
    };
  }

  @override
  OnboardingStep? skip() => null;
}
