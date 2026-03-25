import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

// #Pangea
const notificationOpenedCheckInTypeKey = 'content_check_in_type';
const notificationOpenedSessionIdKey =
    'content_pangea.activity.session_room_id';
const notificationOpenedActivityIdKey = 'content_pangea.activity.id';

Future<void> sendBotNotificationOpenedEvent({
  required Client client,
  required String roomId,
  required String? notificationEventId,
  required String? checkInType,
}) async {
  if (notificationEventId == null || notificationEventId.isEmpty) return;
  if (checkInType == null || checkInType.isEmpty) return;

  try {
    await client.roomsLoading;
    await client.accountDataLoading;

    var room = client.getRoomById(roomId);
    if (room == null) {
      await client
          .waitForRoomInSync(roomId)
          .timeout(const Duration(seconds: 30));
      room = client.getRoomById(roomId);
    }
    if (room == null) return;

    await room.sendEvent({
      'notification_event_id': notificationEventId,
      'check_in_type': checkInType,
      'opened_at_ts': DateTime.now().millisecondsSinceEpoch,
    }, type: PangeaEventTypes.botNotificationOpened);
  } catch (err, s) {
    ErrorHandler.logError(
      e: err,
      s: s,
      data: {
        'roomId': roomId,
        'notificationEventId': notificationEventId,
        'checkInType': checkInType,
      },
    );
  }
}

Future<void> handleBotNotificationTap({
  required Client client,
  required String roomId,
  required String? notificationEventId,
  required String? checkInType,
  required String? sessionRoomId,
  required String? activityId,
  GoRouter? router,
}) async {
  unawaited(
    sendBotNotificationOpenedEvent(
      client: client,
      roomId: roomId,
      notificationEventId: notificationEventId,
      checkInType: checkInType,
    ),
  );

  if (router == null) {
    Logs().v('Ignore select notification action in background mode');
    return;
  }

  Logs().v('Open room from notification tap', roomId);
  await client.roomsLoading;
  await client.accountDataLoading;
  if (client.getRoomById(roomId) == null) {
    await client.waitForRoomInSync(roomId).timeout(const Duration(seconds: 30));
  }

  if (sessionRoomId != null &&
      sessionRoomId.isNotEmpty &&
      activityId != null &&
      activityId.isNotEmpty) {
    try {
      final course = client.getRoomById(roomId);
      if (course == null) return;

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

  final room = client.getRoomById(roomId);
  if (room?.membership == Membership.invite) {
    router.go('/rooms');
  } else if (room?.isSpace == true) {
    router.go('/rooms/spaces/$roomId');
  } else {
    router.go('/rooms/$roomId');
  }
}

// Pangea#
