import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/routes/onboarding/onboarding_client_extension.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_cefr_level_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/user_type_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';

/// The pages onboarding opens with: the page it opens on last, the pages
/// before it behind Back. A new run opens on the profile page. An unfinished
/// one ([OnboardingClientExtension.onboardingUnfinished]) opens on the first
/// page whose data isn't saved to the account, with what is saved in [state]
/// (onboarding.instructions.md § What onboarding reads and saves).
///
/// The profile page is told apart by its own mark, since sign-up already sets
/// a name. The class-code page saves nothing to the account, so the languages
/// decide. The level has a default and always reads as saved, so a run with
/// its languages saved opens on the level page with the saved level selected.
List<OnboardingStep> resumedOnboardingPath(
  Client client,
  OnboardingStateController state,
) {
  final profile = ProfileSetupOnboardingStep(
    client: client,
    state: state,
    maxRemainingSteps: 5,
  );
  if (!client.onboardingUnfinished) return [profile];

  final roleStep = UserTypeOnboardingStep(
    client: client,
    state: state,
    maxRemainingSteps: 4,
  );
  final role = state.userType;
  if (role == null) {
    return client.onboardingProfileSaved ? [profile, roleStep] : [profile];
  }

  final teacher = role == UserType.teacher;
  final codePath = [
    profile,
    roleStep,
    CourseCodeOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: teacher ? 3 : 2,
    ),
  ];

  final settings = client.savedUserSettings;
  final base = PLanguageStore.byLangCode(settings?.sourceLanguage ?? '');
  final target = PLanguageStore.byLangCode(settings?.targetLanguage ?? '');
  if (base == null || target == null) return codePath;

  state
    ..setBaseLanguage(base)
    ..setTargetLanguage(target);
  return [
    ...codePath,
    PickLanguageOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: teacher ? 2 : 1,
    ),
    PickCefrLevelOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: teacher ? 1 : 0,
    ),
  ];
}
