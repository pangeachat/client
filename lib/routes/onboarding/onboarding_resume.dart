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
/// The profile and class-code pages save nothing that tells them apart from
/// a fresh account, so the role and the languages decide. The level has a
/// default and always reads as saved, so a run with its languages saved opens
/// on the level page with the saved level selected.
List<OnboardingStep> resumedOnboardingPath(
  Client client,
  OnboardingStateController state,
) {
  final profile = ProfileSetupOnboardingStep(
    client: client,
    state: state,
    maxRemainingSteps: 5,
  );
  final role = state.userType;
  if (!client.onboardingUnfinished || role == null) return [profile];

  final teacher = role == UserType.teacher;
  final codePath = [
    profile,
    UserTypeOnboardingStep(client: client, state: state, maxRemainingSteps: 4),
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
