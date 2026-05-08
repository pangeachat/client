import 'dart:async';

import 'package:async/async.dart';
import 'package:matrix/matrix.dart' hide Result, Profile;

import 'package:fluffychat/pangea/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/courses/get_localized_courses_request.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';
import 'package:fluffychat/pangea/user/user_model.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class CourseCodeOnboardingStep extends OnboardingStep {
  final UserType type;

  CourseCodeOnboardingStep({
    required super.client,
    required super.prevStep,
    required this.type,
    required super.totalSteps,
    super.stepIndex = 3,
    super.enableSkip = true,
  });

  String? _courseCode;
  Future<CoursePlanModel> Function(GetLocalizedCoursesRequest)? getCoursePlan;
  Future<Result<JoinResponse>> Function(String, Client)? joinSpaceWithCode;
  Future<void> Function(Profile Function(Profile))? updateProfile;
  Future<String> Function(String)? getCourseIdByRoomId;

  void setup(
    Future<CoursePlanModel> Function(GetLocalizedCoursesRequest) getCoursePlan,
    Future<Result<JoinResponse>> Function(String, Client) joinSpaceWithCode,
    Future<void> Function(Profile Function(Profile)) updateProfile,
    Future<String> Function(String) getCourseIdByRoomId,
  ) {
    this.getCoursePlan = getCoursePlan;
    this.joinSpaceWithCode = joinSpaceWithCode;
    this.updateProfile = updateProfile;
    this.getCourseIdByRoomId = getCourseIdByRoomId;
  }

  void setCourseCode(String? code) => _courseCode = code;

  @override
  bool get enableGoForward => _courseCode != null && _courseCode!.isNotEmpty;

  @override
  Future<OnboardingStep?> execute() async {
    final getCoursePlan = this.getCoursePlan;
    final joinSpaceWithCode = this.joinSpaceWithCode;
    final updateProfile = this.updateProfile;
    final getCourseIdByRoomId = this.getCourseIdByRoomId;

    if (getCoursePlan == null ||
        joinSpaceWithCode == null ||
        updateProfile == null ||
        getCourseIdByRoomId == null) {
      throw StateError("Course code onboarding step is not fully set up");
    }

    final code = _courseCode;
    if (code == null) {
      throw StateError("Course code in null");
    }

    final result = await joinSpaceWithCode(code, client);
    if (result.isError) {
      throw result.asError!;
    }

    final joinResult = result.result!;
    final roomId = joinResult.roomId;
    final courseId = await getCourseIdByRoomId(roomId);
    final request = GetLocalizedCoursesRequest(
      coursePlanIds: [courseId],
      l1: "en",
    );

    final course = await getCoursePlan(request);
    final targetLang = course.targetLanguage;
    final baseLang = course.languageOfInstructions;
    final cefrLevel = course.cefrLevel;

    await updateProfile((profile) {
      return profile.copyWith(
        userSettings: profile.userSettings.copyWith(
          targetLanguage: targetLang,
          sourceLanguage: baseLang,
          cefrLevel: cefrLevel,
        ),
      );
    });

    return JoinedCourseOnboardingStep(
      prevStep: this,
      coursePlan: course,
      roomId: roomId,
      client: client,
    );
  }

  @override
  OnboardingStep? skip() => PickLanguageOnboardingStep(
    prevStep: this,
    totalSteps: totalSteps,
    type: type,
    client: client,
  );
}
