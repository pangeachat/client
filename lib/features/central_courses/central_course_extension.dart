import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/course_settings_model.dart';
import 'package:fluffychat/features/central_courses/central_course_rules.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_client_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

extension CentralCourseRoomExtension on Room {
  /// The language this learner's own course is waiting for a plan in, or
  /// null when it isn't one of theirs or already has a plan.
  String? get ownCourseAwaitingPlan {
    if (!isSpace || membership != Membership.join) return null;
    if (getState(EventTypes.RoomCreate)?.senderId != client.userID) {
      return null;
    }
    return CentralCourseRules.awaitingPlanLanguage(
      getState(PangeaEventTypes.coursePlan)?.content,
    );
  }
}

extension CentralCourseClientExtension on Client {
  /// A course still waiting for its plan counts: the learner is in it.
  bool get inAnyCourse => rooms.any(
    (room) =>
        room.isSpace &&
        room.membership == Membership.join &&
        (room.coursePlan != null || room.ownCourseAwaitingPlan != null),
  );

  Future<String> joinCourse(String roomId) async {
    await joinRoom(roomId);
    try {
      await waitForRoomInSync(
        roomId,
        join: true,
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      // Sync lag, not a failed join: the membership is real, and the room
      // arrives with a later sync.
    }
    return roomId;
  }

  /// A private, invite-only course of the learner's own, kept out of Browse:
  /// on [plan] when there is one, otherwise waiting for one in [language].
  Future<String> createOwnCourse({
    required String language,
    CoursePlanModel? plan,
  }) async {
    final roomId = await createPangeaSpace(
      name:
          plan?.title ??
          PLanguageStore.byLangCode(language)?.displayName ??
          language,
      topic: plan?.description,
      avatarUrl: plan?.imageUrl?.toString(),
      visibility: Visibility.private,
      joinRules: JoinRules.invite,
      initialState: [
        StateEvent(
          type: PangeaEventTypes.coursePlan,
          content: plan != null
              ? CoursePlanEvent(uuid: plan.uuid, l2: language).toJson()
              : CentralCourseRules.pendingPlan(language),
        ),
        StateEvent(
          type: PangeaEventTypes.courseSettings,
          content: const CourseSettingsModel(
            requireAnalyticsAccess: true,
          ).toJson(),
        ),
      ],
      spaceChild: 0,
    );
    if (plan != null) await writeNewCourseCopy(roomId, plan.uuid);
    return roomId;
  }

  /// Gives each of the learner's own courses that is waiting for a plan the
  /// plan of its language's central course, once one is found. A course whose
  /// language still has none waits for a later app open.
  Future<void> repairOwnCourses() async {
    for (final room in rooms.toList()) {
      final language = room.ownCourseAwaitingPlan;
      if (language == null) continue;
      final central = await centralCourseFor(language);
      if (central == null) continue;
      try {
        // Also writes the course's own copy of the plan.
        await room.addCourseToSpace(central.courseId, targetLanguage: language);
      } catch (e, s) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {'room_id': room.id, 'target_language': language},
        );
      }
    }
  }
}

/// The app-open half: a learner in no course is offered their language's
/// central course (joining-courses.instructions.md § The central course).
abstract class CentralCourseOffer {
  /// Per user, so overlapping checks can't create two courses.
  static final Set<String> _running = {};

  /// The central course to offer, or null when there is nothing to ask. A
  /// learner in no course whose language has no central course, or whose
  /// lookup failed, gets their own course with no plan instead.
  static Future<PublicCoursesChunk?> dueOnOpen(Client client) async {
    await client.roomsLoading;
    await client.accountDataLoading;
    final user = MatrixState.pangeaController.userController;
    await user.initialize();

    final userId = client.userID;
    final role = user.profile.userSettings.selfIdentifiedRole;
    final language = user.userL2?.langCodeShort;
    if (userId == null ||
        role == UserType.teacher ||
        language == null ||
        !_running.add(userId)) {
      return null;
    }
    try {
      await client.repairOwnCourses();
      if (!CentralCourseRules.qualifies(
        role: role,
        language: language,
        inAnyCourse: client.inAnyCourse,
      )) {
        return null;
      }
      final central = await client.centralCourseFor(language);
      if (central != null) return central;
      await client.createOwnCourse(language: language);
      return null;
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'target_language': language});
      return null;
    } finally {
      _running.remove(userId);
    }
  }
}
