import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/bot/utils/bot_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

class NotificationTapUtil {
  static const _checkInTypeKey = 'content_check_in_type';
  static const _sessionIdKey = 'content_pangea.activity.session_room_id';
  static const _activityIdKey = 'content_pangea.activity.id';

  static Future<void> _ensureRoomLoaded(Client client, String roomId) async {
    await client.roomsLoading;
    await client.accountDataLoading;
    if (client.getRoomById(roomId) == null) {
      await client
          .waitForRoomInSync(roomId)
          .timeout(const Duration(seconds: 30));
    }
  }

  static Future<void> _handleCheckinContent(
    Room room, {
    String? notificationEventId,
    String? checkInType,
  }) async {
    if (notificationEventId == null ||
        notificationEventId.isEmpty ||
        checkInType == null ||
        checkInType.isEmpty) {
      return;
    }

    try {
      await room.sendNotificationOpenedEvent(
        notificationEventId,
        checkInType: checkInType,
      );
    } catch (err, s) {
      ErrorHandler.logError(
        e: err,
        s: s,
        data: {
          'roomId': room.id,
          'notificationEventId': notificationEventId,
          'checkInType': checkInType,
        },
      );
    }
  }

  static void _navigateToActivitySession({
    required Client client,
    required GoRouter router,
    required String roomId,
    required String sessionRoomId,
    required String activityId,
  }) {
    try {
      final session = client.getRoomById(sessionRoomId);
      if (session?.membership == Membership.join) {
        router.go('/rooms/$sessionRoomId');
        return;
      }

      router.go(
        '/rooms/spaces/$roomId/activity/$activityId?roomid=$sessionRoomId',
      );
      return;
    } catch (err, s) {
      ErrorHandler.logError(e: err, s: s, data: {'roomId': sessionRoomId});
    }
  }

  static Future<void> handleNotificationTap({
    required Client client,
    required String roomId,
    required Map<String, dynamic>? notification,
    GoRouter? router,
  }) async {
    Logs().v('Open room from notification tap', roomId);
    await _ensureRoomLoaded(client, roomId);

    final room = client.getRoomById(roomId);
    if (room == null) {
      Logs().w('Room not found after waiting for sync', roomId);
      return;
    }

    final notificationEventId = notification?['event_id'] as String?;
    final checkInType = notification?[_checkInTypeKey] as String?;

    await _handleCheckinContent(
      room,
      notificationEventId: notificationEventId,
      checkInType: checkInType,
    );

    if (router == null) {
      Logs().v('Ignore select notification action in background mode');
      return;
    }

    final sessionRoomId = notification?[_sessionIdKey] as String?;
    final activityId = notification?[_activityIdKey] as String?;

    if (sessionRoomId != null &&
        sessionRoomId.isNotEmpty &&
        activityId != null &&
        activityId.isNotEmpty) {
      _navigateToActivitySession(
        client: client,
        router: router,
        roomId: roomId,
        sessionRoomId: sessionRoomId,
        activityId: activityId,
      );
      return;
    }

    if (room.membership == Membership.invite) {
      router.go('/rooms');
    } else if (room.isSpace == true) {
      router.go('/rooms/spaces/$roomId');
    } else {
      router.go('/rooms/$roomId');
    }
  }
}
