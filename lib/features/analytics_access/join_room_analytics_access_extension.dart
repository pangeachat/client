import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/analytics_constants.dart';
import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics_access/access_notice_extension.dart';
import 'package:fluffychat/features/analytics_access/course_settings_extension.dart';
import 'package:fluffychat/features/analytics_access/grant_analytics_access_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

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

  LanguageModel? _languageByCode(String? langCode) {
    if (langCode == null || langCode.isEmpty) return null;
    return PLanguageStore.byLangCode(langCode) ??
        LanguageModel(langCode: langCode, displayName: langCode);
  }

  /// The course's target language. Prefer the course room's OWN
  /// `pangea.course_plan` `l2` (already in local state — no network, so it works
  /// on a lagging fresh-page-load sync); fall back to the localized plan fetch.
  Future<LanguageModel?> _getCourseLanguage(Room room) async {
    final coursePlan = room.coursePlan;
    final languageFromRoom = _languageByCode(coursePlan?.l2);
    if (languageFromRoom != null) return languageFromRoom;

    final courseId = coursePlan?.uuid;
    return courseId == null ? null : _getCourseLanguageByCourseId(courseId);
  }

  Future<LanguageModel?> _getCourseLanguageByCourseId(String courseId) async {
    final course = await QuestPlansRepo.get(courseId);
    return _languageByCode(course?.targetLanguage);
  }

  Future<Map<String, LanguageModel?>> _getCourseLanguages(
    List<String> courseIds,
  ) async {
    final output = <String, LanguageModel?>{};
    for (final courseId in courseIds) {
      output[courseId] = await _getCourseLanguageByCourseId(courseId);
    }
    return output;
  }

  /// The student's OWN analytics room id for [lang] as recorded in their
  /// server-side `pangea.analytics_profile` — the SAME source the teacher
  /// dashboard reads to resolve a student's analytics room. Fetched fresh (no
  /// cache) so it does NOT depend on the analytics room having surfaced in the
  /// local sync. Matches both the short and full language-code keys the profile
  /// may use. Null when the profile has no room for the language, or on error.
  Future<String?> _ownAnalyticsRoomIdFromPublicProfile(
    LanguageModel lang,
  ) async {
    try {
      final userId = userID;
      if (userId == null) return null;

      final profile = await getUserProfile(userId, maxCacheAge: Duration.zero);
      final analyticsProfile =
          profile.additionalProperties[PangeaEventTypes.profileAnalytics];
      if (analyticsProfile is! Map) return null;

      final analytics = analyticsProfile[AnalyticsConstants.analytics];
      if (analytics is! Map) return null;

      final entry = analytics[lang.langCodeShort] ?? analytics[lang.langCode];
      if (entry is! Map) return null;

      final roomId = entry[AnalyticsConstants.analyticsRoomId];
      return roomId is String && roomId.isNotEmpty ? roomId : null;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"requested_lang": lang.langCode},
      );
      return null;
    }
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

      final languageModel = await _getCourseLanguage(room);
      if (languageModel == null) {
        ErrorHandler.logError(
          e: "Failed to derive language model from course target language",
          data: {"course_id": courseId},
        );
        return;
      }

      // Resolve the analytics room to grant the instructor into. Prefer the
      // SERVER-RECORDED id from the student's own analytics profile
      // (`pangea.analytics_profile`) — the SAME source the teacher dashboard
      // reads to decide granted-vs-pending, fetched fresh so it does NOT depend
      // on the room having surfaced in the local sync yet. Fall back to the
      // local canonical room. The old code used ONLY the local room, which on a
      // required-course join (a fresh page load whose initial sync lags) was
      // routinely still null, so the grant module was never called and the
      // instructor stayed "pending"/"awaiting" on the dashboard forever, even
      // after the student accepted (admin-dash#35, scenario 2).
      final analyticsRoomId =
          await _ownAnalyticsRoomIdFromPublicProfile(languageModel) ??
          ownAnalyticsRoomLocal(lang: languageModel)?.id;
      if (analyticsRoomId == null) {
        // Genuinely no analytics room for this language yet (the student has not
        // studied it). NOT the bug above: a later first-practice creates the
        // room and `grantAnalyticsAccessByAnalyticsRoom` (fired on room
        // creation) grants the instructors then.
        Logs().w(
          "User has no analytics room for course target language ${languageModel.langCode}",
        );
        return;
      }

      await grantInstructorAnalyticsAccess(roomId, analyticsRoomId);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"joining_room_id": roomId},
        level: PangeaHttpException.severityOf(e),
      );
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
        level: PangeaHttpException.severityOf(e),
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
