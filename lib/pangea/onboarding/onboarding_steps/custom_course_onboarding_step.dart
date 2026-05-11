import 'package:async/async.dart';

import 'package:fluffychat/pangea/custom_courses/custom_course_request_model.dart';
import 'package:fluffychat/pangea/custom_courses/custom_course_response_model.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';

class CustomCourseOnboardingStep extends OnboardingStep {
  final LanguageModel baseLanguage;
  final LanguageModel targetLanguage;
  final LanguageLevelTypeEnum languageLevel;

  CustomCourseOnboardingStep({
    required super.client,
    required super.maxTotalSteps,
    super.enableSkip = true,
    required this.baseLanguage,
    required this.targetLanguage,
    required this.languageLevel,
  });

  Future<Result<CustomCourseResponseModel>> Function(
    CustomCourseRequestModel request,
  )?
  _requestCustomCourse;

  String? _name;
  String? _institution;
  String? _goals;

  void setup(
    Future<Result<CustomCourseResponseModel>> Function(
      CustomCourseRequestModel request,
    )?
    requestCustomCourse,
  ) {
    _requestCustomCourse = requestCustomCourse;
  }

  void setName(String name) => _name = name;
  void setInstitution(String institution) => _institution = institution;
  void setGoals(String goals) => _goals = goals;

  @override
  Future<OnboardingStep?> execute() async {
    final requestCustomCourse = _requestCustomCourse;
    if (requestCustomCourse == null) {
      throw StateError("Custom course onboarding step is not fully set up");
    }

    final name = _name;
    final institution = _institution;
    final goals = _goals;
    if (name == null || institution == null || goals == null) {
      throw StateError(
        "Cannot request custom course without name, institution, and goals",
      );
    }

    final languagePair =
        "${baseLanguage.displayName} -> ${targetLanguage.displayName}";

    final request = CustomCourseRequestModel(
      name: name,
      languagePair: languagePair,
      languageLevel: languageLevel,
      institution: institution,
      goals: goals,
    );

    final resp = await requestCustomCourse(request);
    if (resp.isError) {
      throw resp.asError!;
    }

    return null;
  }

  @override
  OnboardingStep? skip() => null;
}
