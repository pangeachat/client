import 'dart:async';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/bot/bot_target_event_name_enum.dart';
import 'package:fluffychat/pangea/bot/utils/bot_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';

class NotificationTapUtil {
  static const _sessionIdKey = 'content_pangea.activity.session_room_id';
  static const _activityIdKey = 'content_pangea.activity.id';

  static const _targetEventKey = 'content_pangea.analytics.target_event_name';
  static const _variantKey = 'content_pangea.analytics.variant';
  static const _chatIdKey = 'content_pangea.analytics.target_param.chat_id';
  static const _groupIdKey = 'content_pangea.analytics.target_param.group_id';
  static const _botActivityIdKey =
      'content_pangea.analytics.target_param.activity_id';
  static const _roomIdKey = 'content_pangea.analytics.target_param.room_id';
  static const _actionKey = 'content_pangea.analytics.target_param.action';
  static const _nameKey = 'content_pangea.analytics.target_param.name';
  static const _checkInTypeKey = 'content_check_in_type';

  static Future<void> _ensureRoomLoaded(Client client, String roomId) async {
    await client.roomsLoading;
    await client.accountDataLoading;
    if (client.getRoomById(roomId) == null) {
      await client
          .waitForRoomInSync(roomId)
          .timeout(const Duration(seconds: 30));
    }
  }

  static void _handleCheckinContent(
    Room room, {
    required Map<String, dynamic> notification,
  }) {
    final notificationEventId = notification['event_id'] as String?;
    final checkInType = notification[_checkInTypeKey] as String?;
    if (notificationEventId == null ||
        notificationEventId.isEmpty ||
        checkInType == null ||
        checkInType.isEmpty) {
      return;
    }

    room
        .sendNotificationOpenedEvent(
          notificationEventId,
          checkInType: checkInType,
        )
        .catchError((err, s) {
          ErrorHandler.logError(
            e: err,
            s: s,
            data: {
              'roomId': room.id,
              'notificationEventId': notificationEventId,
              'checkInType': checkInType,
            },
          );
        });

    _sendCheckinAnalytics(notification);
  }

  static void _sendCheckinAnalytics(Map<String, dynamic> notification) {
    final targetEventNameEntry = notification[_targetEventKey] as String?;
    final targetEventName = BotTargetEventName.values.firstWhereOrNull(
      (e) => e.name == targetEventNameEntry,
    );

    if (targetEventNameEntry != null && targetEventName == null) {
      ErrorHandler.logError(
        e: Exception('Unknown BotTargetEventName: $targetEventNameEntry'),
        data: {'targetEventNameEntry': targetEventNameEntry},
      );
    }

    if (targetEventName != null) {
      try {
        final variant = notification[_variantKey] as String?;
        final notificationType = notification[_checkInTypeKey] as String?;
        final chatId = notification[_chatIdKey] as String?;
        final groupId = notification[_groupIdKey] as String?;
        final activityId = notification[_botActivityIdKey] as String?;
        final roomId = notification[_roomIdKey] as String?;
        final action = notification[_actionKey] as String?;
        final name = notification[_nameKey] as String?;

        GoogleAnalytics.openBotNotification(
          targetEventName: targetEventName,
          variant: variant,
          notificationType: notificationType,
          chatId: chatId,
          groupId: groupId,
          activityId: activityId,
          roomId: roomId,
          action: action,
          name: name,
        );
      } catch (err, s) {
        ErrorHandler.logError(
          e: err,
          s: s,
          data: {
            'targetEventName': targetEventName.name,
            'notification': notification,
          },
        );
      }
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

    if (notification != null) {
      _handleCheckinContent(room, notification: notification);
    }

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

    Logs().w("Notification Body: $notification");
    if (notification?['type'] == EventTypes.RoomMember &&
        room.membership == Membership.invite &&
        !room.isSpace) {
      final parentCourseId = room.pangeaSpaceParents
          .firstWhereOrNull((p) => p.membership == Membership.join)
          ?.id;

      if (parentCourseId != null) {
        router.go('/rooms/spaces/$parentCourseId');
        return;
      }
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
