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
      // hung backend must not lock the UI. Sharing uses whatever courses DID
      // resolve; completeness only gates the source_course_id pin elsewhere.
      matching = (await ActivityCourseResolver.matchingCourseSpaces(
        this,
        activity.activityId,
        activity.req.targetLanguage,
      ).timeout(const Duration(seconds: 10))).matches;
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
          // Pin history visibility to `shared` at creation rather than relying
          // on the server default. A session room is a shared, course-scoped
          // conversation: a teacher who joins to review it — or a coursemate who
          // knocks in partway through — must be able to read what was said
          // BEFORE they joined, which the `joined`/`invited` defaults forbid.
          // Sending it as INITIAL state also means it is set atomically at
          // creation, so there is no window in which early messages land under a
          // stricter rule and stay unreadable forever.
          //
          // `shared` (not `world_readable`): history is open to room members,
          // never to non-members, and the room is created `private` with a
          // knock/knock-restricted join rule, so membership stays the gate.
          //
          // Rooms created before this shipped keep whatever default they got;
          // history visibility is not retroactive, so this fixes the future
          // only, and readers must still degrade gracefully to post-join-only
          // history for older sessions.
          StateEvent(
            type: EventTypes.HistoryVisibility,
            content: {'history_visibility': HistoryVisibility.shared.text},
          ),
        ],
        // Seeds the bot at PL 50 so it can write its state events without
        // the self-promotion dance that overloaded staging Synapse
        // (pangea-bot#1409). Same bot-id source as the invite below.
        powerLevelContentOverride: RoomDefaults.defaultPowerLevelsContent(
          ownUserId: userID!,
          botUserId: BotName.byEnvironment,
        ),
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

    // Invite the bot so it is present in every session from the start — idle (no
    // role, no messages) until the room admin chooses "play with bot", which
    // writes pangea.bot_participant (the bot's gate to claim a role). On the
    // "invite a friend" path no marker is written, so the seat stays open and the
    // bot moderates silently once the friend joins (#2595, #7027).
    //
    // Best-effort AND by room id (not the local Room object): inviteUser targets
    // the homeserver directly, so it neither fails session creation on a transient
    // invite error nor races the fresh room syncing into the local store — the old
    // getRoomById(roomID) == null path silently skipped the invite, leaving the
    // marker written but no bot in the room.
    try {
      await inviteUser(roomID, BotName.byEnvironment);
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
