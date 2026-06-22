import 'dart:async';

import 'package:matrix/matrix.dart' as sdk;
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/world/activity_course_resolver.dart';

extension LaunchActivitySession on Client {
  /// Create an activity session room and share it into every joined
  /// course space whose plan includes the activity with a matching L2,
  /// so teachers and coursemates can see and join the session.
  ///
  /// [primarySpace] (the space the user launched from, if any) is always
  /// included. With no matching spaces the session is created private
  /// with a plain knock join rule.
  Future<String> launchActivitySession(
    ActivityPlanModel activity,
    ActivityRole? role, {
    Room? primarySpace,
  }) async {
    List<Room> matching = [];
    try {
      // Bounded: this runs inside a blocking loading dialog; a slow or
      // hung backend must not lock the UI.
      matching = await ActivityCourseResolver.matchingCourseSpaces(
        this,
        activity.activityId,
        activity.req.targetLanguage,
      ).timeout(const Duration(seconds: 10));
    } catch (e, s) {
      // Sharing is best-effort; session creation must not fail on it.
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'activityId': activity.activityId},
        level: SentryLevel.warning,
      );
    }
    final spaces = <String, Room>{
      ?primarySpace?.id: ?primarySpace,
      for (final space in matching) space.id: space,
    };

    final roomID = await createPangeaRoom(
      createRoom(
        creationContent: {
          'type': "${PangeaRoomTypes.activitySession}:${activity.activityId}",
        },
        visibility: sdk.Visibility.private,
        name: activity.title,
        topic: activity.description,
        initialState: [
          // Thin reference, not the embedded plan: the body stays canonical in
          // CMS and is fetched live per-viewer. Pin the version at creation so
          // scoring is stable against later owner edits. See
          // activities.instructions.md.
          StateEvent(
            type: PangeaEventTypes.activityPlan,
            content: {
              ActivitySessionConstants.activityId: activity.activityId,
              if (activity.versionId != null)
                ActivitySessionConstants.versionId: activity.versionId,
              if (primarySpace != null)
                ActivitySessionConstants.sourceCourseId: primarySpace.id,
            },
          ),
          if (activity.imageURL != null)
            StateEvent(
              type: EventTypes.RoomAvatar,
              content: {'url': activity.imageURL!.toString()},
            ),
          if (role != null)
            StateEvent(
              type: PangeaEventTypes.activityRole,
              content: ActivityRolesModel({
                role.id: ActivityRoleModel(
                  id: role.id,
                  userId: userID!,
                  role: role.name,
                ),
              }).toJson(),
            ),
          await generateCustomJoinRules(
            spaces.isEmpty ? JoinRules.knock : JoinRules.knockRestricted,
            allowRoomIds: spaces.keys.toList(),
          ),
        ],
        powerLevelContentOverride: RoomDefaults.defaultPowerLevelsContent,
      ),
    );

    for (final space in spaces.values) {
      try {
        await space.addSpaceChildKeepingParents(roomID);
      } catch (e, s) {
        // One space failing to attach must not block the others or the
        // session itself (e.g. insufficient power level in that space).
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {'roomId': roomID, 'spaceId': space.id},
          level: SentryLevel.warning,
        );
      }
    }

    try {
      await waitForRoomInSync(roomID).timeout(const Duration(seconds: 10));
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': roomID},
        level: e is TimeoutException ? SentryLevel.warning : SentryLevel.error,
      );
      if (e is! TimeoutException) rethrow;
    }

    // Auto-invite the bot so it is present in every session from the start, but
    // it stays idle (no role, no messages) until the user makes an explicit
    // choice on the start page ("play with bot" or "invite a friend"), which
    // writes pangea.activity_started. That marker is the bot's gate to claim a
    // role, so the choice page is never bypassed. The bot adapts live thereafter:
    // participant while alone with one human, silent moderator once a second
    // human joins (#2595, #7027). Best-effort: must not fail session creation.
    try {
      final botRoom = getRoomById(roomID);
      if (botRoom == null) {
        ErrorHandler.logError(
          m: 'Auto-invite skipped: activity room not found after sync',
          data: {'roomId': roomID},
          level: SentryLevel.warning,
        );
      } else {
        await botRoom.invite(BotName.byEnvironment);
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': roomID},
        level: SentryLevel.warning,
      );
    }

    return roomID;
  }
}
