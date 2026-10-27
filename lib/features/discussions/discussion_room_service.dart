import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart' as sdk;
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/discussions/discussion_extensions.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/chat_list/course_hierarchy_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// What a discussion card or pin opens (#9647): the learner's own room for the
/// discussion if they have one, else the fullest of the course's rooms for it
/// that still has space, else a new room. The learner is never asked to pick
/// one.
class DiscussionRoomService {
  const DiscussionRoomService._();

  /// The room id to open for [activityId] in [course], joining or creating
  /// it behind a loading dialog; null if that failed (the dialog shows why).
  static Future<String?> open(
    BuildContext context, {
    required Room course,
    required String activityId,
    required String question,
    required String? missionId,
    Uri? imageUrl,
  }) async {
    final client = course.client;
    final own = client.discussionRoomsFor(activityId).firstOrNull;
    if (own != null) return own.id;
    final resp = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final roomId =
            await _joinOpenRoom(course, activityId) ??
            await _createRoom(
              course,
              activityId: activityId,
              question: question,
              missionId: missionId,
              imageUrl: imageUrl,
            );
        await _mentionsOnly(client, roomId);
        return roomId;
      },
    );
    return resp.result;
  }

  /// Joins the fullest of [course]'s rooms for [activityId] that is under
  /// capacity, and returns its id; null when there is none.
  static Future<String?> _joinOpenRoom(Room course, String activityId) async {
    final type = '${PangeaRoomTypes.discussion}:$activityId';
    final open = await course
        .hierarchyChildren()
        .where(
          (c) =>
              c.roomType == type &&
              c.numJoinedMembers < DiscussionIds.roomCapacity,
        )
        .toList();
    if (open.isEmpty) return null;
    // Fill one room before the next, so learners meet each other.
    open.sort((a, b) => b.numJoinedMembers.compareTo(a.numJoinedMembers));
    final roomId = open.first.roomId;
    final client = course.client;
    await client.joinRoom(
      roomId,
      via: course.spaceChildren
          .firstWhereOrNull((child) => child.roomId == roomId)
          ?.via,
    );
    final joined = client.getRoomById(roomId);
    if (joined == null || joined.membership != Membership.join) {
      await client.waitForRoomInSync(roomId, join: true);
    }
    return roomId;
  }

  static Future<String> _createRoom(
    Room course, {
    required String activityId,
    required String question,
    required String? missionId,
    Uri? imageUrl,
  }) async {
    final client = course.client;
    final userId = client.userID!;
    final joinRules = await client.generateCustomJoinRules(
      JoinRules.knockRestricted,
      allowRoomIds: [course.id],
    );
    final roomId = await client.createPangeaRoom(
      client.createRoom(
        creationContent: {'type': '${PangeaRoomTypes.discussion}:$activityId'},
        visibility: sdk.Visibility.private,
        name: question,
        topic: question,
        initialState: [
          StateEvent(
            type: DiscussionIds.stateEvent,
            content: {
              'activity_id': activityId,
              'mission_id': ?missionId,
              'course_id': course.id,
            },
          ),
          StateEvent(
            type: PangeaEventTypes.capacity,
            content: {'capacity': DiscussionIds.roomCapacity},
          ),
          if (imageUrl != null)
            StateEvent(
              type: EventTypes.RoomAvatar,
              content: {'url': imageUrl.toString()},
            ),
          joinRules,
          // Members who join later read what was said before them.
          StateEvent(
            type: EventTypes.HistoryVisibility,
            content: {'history_visibility': HistoryVisibility.shared.text},
          ),
        ],
        powerLevelContentOverride: RoomDefaults.defaultPowerLevelsContent(
          ownUserId: userId,
          botUserId: BotName.byEnvironment,
        ),
      ),
      waitForSync: false,
    );
    if (client.getRoomById(roomId) == null) {
      await client.waitForRoomInSync(roomId, join: true);
    }
    // Shared into the course so coursemates find it and the teacher sees it.
    // No bot for now: it greets on join and replies off-topic in a plain
    // group room (#9647).
    unawaited(_shareIntoCourse(course, roomId));
    return roomId;
  }

  static Future<void> _shareIntoCourse(Room course, String roomId) async {
    try {
      await course.addSpaceChildKeepingParents(roomId);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': roomId, 'courseId': course.id},
        level: SentryLevel.warning,
      );
    }
  }

  /// A discussion notifies the learner only when someone mentions them: they
  /// may have said their piece already.
  static Future<void> _mentionsOnly(Client client, String roomId) async {
    final room = client.getRoomById(roomId);
    if (room == null || room.pushRuleState == PushRuleState.mentionsOnly) {
      return;
    }
    try {
      await room.setPushRuleState(PushRuleState.mentionsOnly);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': roomId},
        level: SentryLevel.warning,
      );
    }
  }
}
