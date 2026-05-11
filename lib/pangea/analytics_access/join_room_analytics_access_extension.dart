import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_access/access_notice_extension.dart';
import 'package:fluffychat/pangea/analytics_access/course_settings_extension.dart';
import 'package:fluffychat/pangea/analytics_access/grant_analytics_access_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plans_repo.dart';
import 'package:fluffychat/pangea/course_plans/courses/get_localized_courses_request.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';
import 'package:fluffychat/widgets/matrix.dart';

class JoinResponse {
  final String roomId;
  final bool shouldShowNotice;

  const JoinResponse({required this.roomId, required this.shouldShowNotice});
}

extension JoinRoomAnalyticsAccessClientExtension on Client {
  Future<JoinResponse> joinRoomWithAccessCheck(
    String roomIdOrAlias, {
    List<String>? serverName,
    List<String>? via,
    String? reason,
    ThirdPartySigned? thirdPartySigned,
  }) async {
    final resp = await joinRoom(
      roomIdOrAlias,
      serverName: serverName,
      via: via,
      reason: reason,
      thirdPartySigned: thirdPartySigned,
    );

    final room = await _loadRoom(resp);
    final joinResp = JoinResponse(
      roomId: resp,
      shouldShowNotice: room.shouldShowAnalyticsAccessNotice,
    );
    return joinResp;
  }

  Future<JoinResponse> joinRoomByIdWithAccessCheck(
    String roomId, {
    String? reason,
    ThirdPartySigned? thirdPartySigned,
  }) async {
    final resp = await joinRoomById(
      roomId,
      reason: reason,
      thirdPartySigned: thirdPartySigned,
    );
    final room = await _loadRoom(resp);
    final joinResp = JoinResponse(
      roomId: roomId,
      shouldShowNotice: room.shouldShowAnalyticsAccessNotice,
    );
    return joinResp;
  }

  Future<Room> _loadRoom(String roomId) async {
    Room? room = getRoomById(roomId);
    if (room == null || room.membership != Membership.join) {
      await waitForRoomInSync(
        roomId,
        join: true,
      ).timeout(Duration(seconds: 10));
    }

    room = getRoomById(roomId);
    if (room == null) {
      throw "Room not found after joining";
    }

    return room;
  }

  Future<LanguageModel?> _getCourseLanguage(
    String courseId,
    String langCode,
  ) async {
    final request = GetLocalizedCoursesRequest(
      coursePlanIds: [courseId],
      l1: langCode,
    );
    final course = await CoursePlansRepo.get(request);
    final targetLanguage = course.targetLanguage;
    return PLanguageStore.byLangCode(targetLanguage);
  }

  Future<Map<String, LanguageModel?>> _getCourseLanguages(
    List<String> courseIds,
    String langCode,
  ) async {
    final request = GetLocalizedCoursesRequest(
      coursePlanIds: courseIds,
      l1: langCode,
    );
    final resp = await CoursePlansRepo.search(request);
    final coursePlans = resp.coursePlans;
    final Map<String, LanguageModel?> output = {};
    for (final courseId in courseIds) {
      final plan = coursePlans[courseId];
      final targetLanguage = plan?.targetLanguage;
      LanguageModel? languageModel;
      if (targetLanguage != null) {
        languageModel = PLanguageStore.byLangCode(targetLanguage);
      }
      output[courseId] = languageModel;
    }
    return output;
  }

  Future<void> grantInstructorsAnalyticsAccess(String roomId) async {
    try {
      final room = getRoomById(roomId);
      if (room == null) {
        ErrorHandler.logError(
          e: "Room is null in _grantAnalyticsAccess",
          data: {"analytics_access_room_id": roomId},
        );
        return;
      }

      final courseId = room.coursePlan?.uuid;
      if (courseId == null) {
        Logs().w("Room without courseID in _grantAnalyticsAccess");
        return;
      }

      final userL1 =
          MatrixState.pangeaController.userController.userL1Code ?? 'en';
      final languageModel = await _getCourseLanguage(courseId, userL1);
      if (languageModel == null) {
        ErrorHandler.logError(
          e: "Failed to derive language model from course target language",
          data: {"course_id": courseId},
        );
        return;
      }

      final analyticsRoom = analyticsRoomLocal(languageModel);
      if (analyticsRoom == null) {
        Logs().w(
          "User has no analytics room for course target language ${languageModel.langCode}",
        );
        return;
      }

      await grantInstructorAnalyticsAccess(roomId, analyticsRoom.id);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"joining_room_id": roomId});
    }
  }

  Future<void> grantAnalyticsAccessByAnalyticsRoom(
    String analyticsRoomId,
    String analyticsLangCode,
  ) async {
    try {
      final roomIdToCourseId = Map<String, String>.fromEntries(
        rooms
            .where((r) => r.requireAnalyticsAccess && r.coursePlan != null)
            .map((r) => MapEntry(r.id, r.coursePlan!.uuid)),
      );

      final userL1 =
          MatrixState.pangeaController.userController.userL1Code ?? 'en';

      final languages = await _getCourseLanguages(
        roomIdToCourseId.values.toList(),
        userL1,
      );

      final grantFutures = <Future>[];
      for (final entry in roomIdToCourseId.entries) {
        final roomId = entry.key;
        final courseId = entry.value;
        final lang = languages[courseId];
        if (lang?.langCodeShort == analyticsLangCode) {
          grantFutures.add(
            grantInstructorAnalyticsAccess(roomId, analyticsRoomId),
          );
        }
      }
      await Future.wait(grantFutures);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "analytics_room_id": analyticsRoomId,
          "analytics_lang_code": analyticsLangCode,
        },
      );
    }
  }
}

extension JoinRoomAnalyticsAccessRoomExtension on Room {
  bool get shouldShowAnalyticsAccessNotice =>
      requireAnalyticsAccess && !client.sawAccessNotice(id);

  Future<JoinResponse?> joinWithAccessCheck() async {
    await join();
    final room = await client._loadRoom(id);
    final joinResp = JoinResponse(
      roomId: id,
      shouldShowNotice: room.shouldShowAnalyticsAccessNotice,
    );
    return joinResp;
  }
}
