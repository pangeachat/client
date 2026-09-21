import 'package:async/async.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/join_codes/space_code_controller.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/onboarding/custom_course_repo.dart';
import 'package:fluffychat/routes/onboarding/custom_course_request_model.dart';
import 'package:fluffychat/routes/onboarding/custom_course_response_model.dart';
import 'package:fluffychat/routes/onboarding/onboarding_client_extension.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

abstract class CourseProvider {
  String? getCachedJoinCode();

  /// Drop the cached inbound join code once onboarding is finished with it
  /// (joined on success, handed off to manual entry on failure). A leftover
  /// would surprise-join a later login (#7524).
  Future<void> clearCachedJoinCode();

  Future<String> joinSpaceWithCode(String code);

  /// The joined course's quest, or null when it cannot be resolved — a space
  /// pointing at a retired plan id, or a content service that didn't answer.
  /// The join still stands, so onboarding continues without the course's
  /// details (#8593).
  Future<CoursePlanModel?> getCourseByRoomId(String roomId);

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
  Future<void> clearCachedJoinCode() => SpaceCodeRepo.clearSpaceCode();

  @override
  Future<String> joinSpaceWithCode(String code) async {
    final result = await SpaceCodeController.joinSpaceWithCode(
      code,
      client: client,
    );
    final joinResp = result.result;
    if (joinResp == null) {
      // Rethrow the underlying failure with its own stack: throwing the
      // Result wrapper gave Sentry the blind "Instance of 'ErrorResult'"
      // title (#8693).
      final error = result.asError;
      if (error != null) {
        Error.throwWithStackTrace(error.error, error.stackTrace);
      }
      throw Exception("Failed to join space with code");
    }

    return joinResp.roomId;
  }

  @override
  Future<CoursePlanModel?> getCourseByRoomId(String roomId) async {
    try {
      final courseId = await client.getCourseIdByRoomId(roomId);
      final quest = await QuestPlansRepo.get(courseId);
      if (quest == null) {
        // Reported once per course: an orphaned course re-fails for every user
        // who joins it, and each repeat carries no new signal (#8083).
        await ErrorHandler.logErrorOnce(
          key: 'onboarding-course-load:$courseId',
          e: Exception('No quest plan found for course $courseId'),
          data: {'roomId': roomId},
        );
      }
      return quest;
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'roomId': roomId});
      return null;
    }
  }

  @override
  Future<Result<CustomCourseResponseModel>> requestCustomCourse(
    CustomCourseRequestModel request,
  ) => CustomCourseRepo.instance.get(request);
}

class MockCourseProvider implements CourseProvider {
  @override
  String? getCachedJoinCode() => null;

  @override
  Future<void> clearCachedJoinCode() async {}

  @override
  Future<String> joinSpaceWithCode(String code) async =>
      '!aeSvkSZmeiXqgwLVNS:staging.pangea.chat';

  @override
  Future<CoursePlanModel?> getCourseByRoomId(String roomId) async =>
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
