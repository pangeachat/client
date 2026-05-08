import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plans_repo.dart';
import 'package:fluffychat/pangea/course_plans/courses/get_localized_courses_request.dart';
import 'package:fluffychat/pangea/join_codes/space_code_controller.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class CourseCodeOnboardingStep extends OnboardingStep {
  final UserType type;

  CourseCodeOnboardingStep({
    required super.client,
    super.stepIndex = 3,
    required super.totalSteps,
    required super.prevStep,
    required this.type,
    super.canSkip = true,
  });

  bool _skip = false;
  String? _courseCode;

  CoursePlanModel? _coursePlan;
  String? _courseRoomId;

  void skip() => _skip = true;
  void setCourseCode(String? code) => _courseCode = code;
  void setCoursePlan(CoursePlanModel? coursePlan) => _coursePlan = coursePlan;

  @override
  bool get enableGoForward =>
      _skip || (_courseCode != null && _courseCode!.isNotEmpty);

  @override
  OnboardingStep? get nextStep {
    if (_skip) {
      return PickLanguageOnboardingStep(
        prevStep: this,
        totalSteps: totalSteps,
        type: type,
        client: client,
      );
    }

    final courseRoomId = _courseRoomId;
    if (courseRoomId == null) {
      throw StateError(
        "Cannot move forward without skipping or setting joined course roomID",
      );
    }

    final course = _coursePlan;
    if (course == null) {
      throw StateError(
        "Cannot move forward without skipping or setting joined course",
      );
    }

    return JoinedCourseOnboardingStep(
      prevStep: this,
      coursePlan: course,
      roomId: courseRoomId,
      client: client,
    );
  }

  @override
  Future<void> execute() async {
    if (_skip) return;
    final code = _courseCode;
    if (code == null) {
      throw StateError("Course code in null");
    }

    final result = await SpaceCodeController.joinSpaceWithCode(
      code,
      client: client,
    );

    if (result.isError) {
      throw result.asError!;
    }

    final joinResult = result.result!;
    final roomId = joinResult.roomId;
    Room? room = client.getRoomById(roomId);
    if (room == null || room.membership != Membership.join) {
      await client.waitForRoomInSync(roomId).timeout(Duration(seconds: 10));
    }

    room = client.getRoomById(roomId);
    if (room == null) {
      throw "Room not found";
    }

    final courseId = room.coursePlan?.uuid;
    if (courseId == null) {
      throw "Joined room does not have courseID";
    }

    final request = GetLocalizedCoursesRequest(
      coursePlanIds: [courseId],
      l1: "en",
    );

    final course = await CoursePlansRepo.get(request);
    _coursePlan = course;
    _courseRoomId = roomId;

    final targetLang = course.targetLanguage;
    final baseLang = course.languageOfInstructions;
    final cefrLevel = course.cefrLevel;

    await MatrixState.pangeaController.userController.updateProfile((profile) {
      return profile.copyWith(
        userSettings: profile.userSettings.copyWith(
          targetLanguage: targetLang,
          sourceLanguage: baseLang,
          cefrLevel: cefrLevel,
        ),
      );
    }, waitForDataInSync: true);
  }
}
