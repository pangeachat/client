import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics_access/access_notice_extension.dart';
import 'package:fluffychat/features/analytics_access/course_settings_extension.dart';
import 'package:fluffychat/features/analytics_access/grant_analytics_access_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

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
      shouldShowNotice: room?.shouldShowAnalyticsAccessNotice ?? false,
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
      shouldShowNotice: room?.shouldShowAnalyticsAccessNotice ?? false,
    );
    return joinResp;
  }

  /// The joined room from local state, waiting briefly for sync to surface it.
  /// Null when sync is still lagging — NOT a failure: every caller runs after
  /// a join API call that already succeeded, so the membership is real and the
  /// local room list just hasn't caught up. A freshly-booted client (a class
  /// join link IS a fresh page load) routinely takes longer than this to chew
  /// through its initial sync; failing the flow here stranded the user on the
  /// join page as a secret member of the course (#7579).
  Future<Room?> _loadRoom(String roomId) async {
    final room = getRoomById(roomId);
    if (room == null || room.membership != Membership.join) {
      try {
        await waitForRoomInSync(
          roomId,
          join: true,
        ).timeout(const Duration(seconds: 10));
      } on TimeoutException {
        // Sync lag, not a failed join — proceed without the local room.
      }
    }
    return getRoomById(roomId);
  }

  Future<LanguageModel?> _getCourseLanguage(String courseId) async {
    final course = await QuestPlansRepo.get(courseId);
    final targetLanguage = course?.targetLanguage;
    return targetLanguage == null
        ? null
        : PLanguageStore.byLangCode(targetLanguage);
  }

  Future<Map<String, LanguageModel?>> _getCourseLanguages(
    List<String> courseIds,
  ) async {
    final output = <String, LanguageModel?>{};
    for (final courseId in courseIds) {
      output[courseId] = await _getCourseLanguage(courseId);
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

      final languageModel = await _getCourseLanguage(courseId);
      if (languageModel == null) {
        ErrorHandler.logError(
          e: "Failed to derive language model from course target language",
          data: {"course_id": courseId},
        );
        return;
      }

      final analyticsRoom = ownAnalyticsRoomLocal(lang: languageModel);
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

      final languages = await _getCourseLanguages(
        roomIdToCourseId.values.toList(),
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
      requireAnalyticsAccess && !client.acceptedAccessNotice(id);

  Future<JoinResponse?> joinWithAccessCheck() async {
    await join();
    final room = await client._loadRoom(id);
    final joinResp = JoinResponse(
      roomId: id,
      shouldShowNotice: room?.shouldShowAnalyticsAccessNotice ?? false,
    );
    return joinResp;
  }
}
