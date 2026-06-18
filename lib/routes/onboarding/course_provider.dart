import 'package:async/async.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/join_codes/space_code_controller.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/routes/onboarding/custom_course_repo.dart';
import 'package:fluffychat/routes/onboarding/custom_course_request_model.dart';
import 'package:fluffychat/routes/onboarding/custom_course_response_model.dart';
import 'package:fluffychat/routes/onboarding/onboarding_client_extension.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

abstract class CourseProvider {
  String? getCachedJoinCode();

  Future<String> joinSpaceWithCode(String code);

  Future<CoursePlanModel> getCourseByRoomId(String roomId);

  Future<Result<CustomCourseResponseModel>> requestCustomCourse(
    CustomCourseRequestModel request,
  );
}

class ClientCourseProvider implements CourseProvider {
  final Client client;
  const ClientCourseProvider({required this.client});

  @override
  String? getCachedJoinCode() => SpaceCodeRepo.spaceCode;

  @override
  Future<String> joinSpaceWithCode(String code) async {
    final result = await SpaceCodeController.joinSpaceWithCode(
      code,
      client: client,
    );
    final joinResp = result.result;
    if (joinResp == null) {
      throw result.asError ?? "Failed to join space with code";
    }

    return joinResp.roomId;
  }

  @override
  Future<CoursePlanModel> getCourseByRoomId(String roomId) async {
    final courseId = await client.getCourseIdByRoomId(roomId);
    final quest = await QuestPlansRepo.get(courseId);
    if (quest == null) {
      throw Exception('No quest plan found for course $courseId');
    }
    return quest;
  }

  @override
  Future<Result<CustomCourseResponseModel>> requestCustomCourse(
    CustomCourseRequestModel request,
  ) => CustomCourseRepo.get(
    request,
    MatrixState.pangeaController.userController.accessToken,
  );
}

class MockCourseProvider implements CourseProvider {
  @override
  String? getCachedJoinCode() => null;

  @override
  Future<String> joinSpaceWithCode(String code) async =>
      '!aeSvkSZmeiXqgwLVNS:staging.pangea.chat';

  @override
  Future<CoursePlanModel> getCourseByRoomId(String roomId) async =>
      CoursePlanModel(
        targetLanguage: "es",
        languageOfInstructions: "en",
        cefrLevel: LanguageLevelTypeEnum.a1,
        title: "Test Course",
        description: "Course for testing",
        topicIds: [],
        mediaIds: [],
        updatedAt: DateTime(2026, 5, 1),
        createdAt: DateTime(2026, 5, 1),
        uuid: "49e6b07f-cf95-44df-9790-3829dce72a12",
      );

  @override
  Future<Result<CustomCourseResponseModel>> requestCustomCourse(
    CustomCourseRequestModel request,
  ) async =>
      Result.value(CustomCourseResponseModel(id: "123", status: "generating"));
}
