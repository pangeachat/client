import 'dart:async';

import 'package:fluffychat/pangea/languages/p_language_store.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';

class CourseCodeOnboardingStep extends OnboardingStep {
  CourseCodeOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
    super.enableSkip = true,
  });

  String? _courseCode;

  @override
  bool get enableGoForward => _courseCode != null && _courseCode!.isNotEmpty;

  void setCourseCode(String? code) => _courseCode = code;

  @override
  Future<OnboardingStep?> execute() async {
    final code = _courseCode;
    if (code == null) {
      throw StateError("Course code in null");
    }

    final roomId = await state.courseProvider.joinSpaceWithCode(code);
    final course = await state.courseProvider.getCourseByRoomId(roomId);

    state.setJoinedRoomId(roomId);
    state.setJoinedCoursePlan(course);

    final targetLangCode = course.targetLanguage;
    final baseLangCode = course.languageOfInstructions;
    final cefrLevel = course.cefrLevel;

    final targetLang = PLanguageStore.byLangCode(targetLangCode);
    final baseLang = PLanguageStore.byLangCode(baseLangCode);

    state.setTargetLanguage(targetLang);
    state.setBaseLanguage(baseLang);
    state.setLanguageLevel(cefrLevel);

    await state.accountUpdater.updateProfile((profile) {
      return profile.copyWith(
        userSettings: profile.userSettings.copyWith(
          targetLanguage: targetLangCode,
          sourceLanguage: baseLangCode,
          cefrLevel: cefrLevel,
        ),
      );
    });

    return JoinedCourseOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: 0,
    );
  }

  @override
  OnboardingStep? skip() {
    final maxRemainingSteps = switch (state.userType) {
      UserType.student => 1,
      UserType.teacher => 2,
      null => 1,
    };

    return PickLanguageOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: maxRemainingSteps,
    );
  }
}
