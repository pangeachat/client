import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/push_helper.dart';
import '../config/app_config.dart';
import '../config/setting_keys.dart';

bool _vodInitialized = false;

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

extension NotificationResponseJson on NotificationResponse {
  String toJsonString() => jsonEncode({
    'type': notificationResponseType.name,
    'id': id,
    'actionId': actionId,
    'input': input,
    'payload': payload,
    'data': data,
  });

  static NotificationResponse fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, Object?>;
    return NotificationResponse(
      notificationResponseType: NotificationResponseType.values.singleWhere(
        (t) => t.name == json['type'],
      ),
      id: json['id'] as int?,
      actionId: json['actionId'] as String?,
      input: json['input'] as String?,
      payload: json['payload'] as String?,
      data: json['data'] as Map<String, dynamic>,
    );
  }
}

Future<void> waitForPushIsolateDone() async {
  if (IsolateNameServer.lookupPortByName(AppConfig.pushIsolatePortName) !=
      null) {
    Logs().i('Wait for Push Isolate to be done...');
    await Future.delayed(const Duration(milliseconds: 300));
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(
  NotificationResponse notificationResponse,
) async {
  final sendPort = IsolateNameServer.lookupPortByName(
    AppConfig.mainIsolatePortName,
  );
  if (sendPort != null) {
    sendPort.send(notificationResponse.toJsonString());
    Logs().i('Notification tap sent to main isolate!');
    return;
  }
  Logs().i(
    'Main isolate no up - Create temporary client for notification tap intend!',
  );

  final pushIsolateReceivePort = ReceivePort();
  IsolateNameServer.registerPortWithName(
    pushIsolateReceivePort.sendPort,
    AppConfig.pushIsolatePortName,
  );

  if (!_vodInitialized) {
    await vod.init();
    _vodInitialized = true;
  }
  final store = await AppSettings.init();
  final client = (await ClientManager.getClients(
    initialize: false,
    store: store,
  )).first;
  await client.abortSync();
  await client.init(
    waitForFirstSync: false,
    waitUntilLoadCompletedLoaded: false,
  );

  if (!client.isLogged()) {
    throw Exception('Notification tab in background but not logged in!');
  }
  try {
    await notificationTap(notificationResponse, client: client);
  } finally {
    await client.dispose(closeDatabase: false);
    pushIsolateReceivePort.sendPort.send('DONE');
    IsolateNameServer.removePortNameMapping(AppConfig.pushIsolatePortName);
  }
  return;
}

Future<void> notificationTap(
  NotificationResponse notificationResponse, {
  GoRouter? router,
  required Client client,
  L10n? l10n,
}) async {
  Logs().d(
    'Notification action handler started',
    notificationResponse.notificationResponseType.name,
  );
  final payload = FluffyChatPushPayload.fromString(
    notificationResponse.payload ?? '',
  );
  switch (notificationResponse.notificationResponseType) {
    case NotificationResponseType.selectedNotification:
      final roomId = payload.roomId;
      if (roomId == null) return;

      await handleBotNotificationTap(
        client: client,
        roomId: roomId,
        notificationEventId: payload.eventId,
        checkInType: payload.additionalData[notificationOpenedCheckInTypeKey],
        sessionRoomId: payload.additionalData[notificationOpenedSessionIdKey],
        activityId: payload.additionalData[notificationOpenedActivityIdKey],
        router: router,
      );
    case NotificationResponseType.selectedNotificationAction:
      final actionType = FluffyChatNotificationActions.values.singleWhereOrNull(
        (action) => action.name == notificationResponse.actionId,
      );
      if (actionType == null) {
        throw Exception('Selected notification with action but no action ID');
      }
      final roomId = payload.roomId;
      if (roomId == null) {
        throw Exception('Selected notification with action but no payload');
      }
      await client.roomsLoading;
      await client.accountDataLoading;
      await client.userDeviceKeysLoading;
      final room = client.getRoomById(roomId);
      if (room == null) {
        throw Exception(
          'Selected notification with action but unknown room $roomId',
        );
      }
      switch (actionType) {
        case FluffyChatNotificationActions.markAsRead:
          await room.setReadMarker(
            payload.eventId ?? room.lastEvent!.eventId,
            mRead: payload.eventId ?? room.lastEvent!.eventId,
            public: AppSettings.sendPublicReadReceipts.value,
          );
        case FluffyChatNotificationActions.reply:
          final input = notificationResponse.input;
          if (input == null || input.isEmpty) {
            throw Exception(
              'Selected notification with reply action but without input',
            );
          }

          final eventId = await room.sendTextEvent(
            input,
            parseCommands: false,
            displayPendingEvent: false,
          );

          if (PlatformInfos.isAndroid) {
            final ownProfile = await room.client.fetchOwnProfile();
            final avatar = ownProfile.avatarUrl;
            final avatarFile = avatar == null
                ? null
                : await client
                      .downloadMxcCached(
                        avatar,
                        thumbnailMethod: ThumbnailMethod.crop,
                        width: notificationAvatarDimension,
                        height: notificationAvatarDimension,
                        animated: false,
                        isThumbnail: true,
                        rounded: true,
                      )
                      .timeout(const Duration(seconds: 3));
            final messagingStyleInformation =
                await AndroidFlutterLocalNotificationsPlugin()
                    .getActiveNotificationMessagingStyle(room.id.hashCode);
            if (messagingStyleInformation == null) return;
            l10n ??= await lookupL10n(PlatformDispatcher.instance.locale);
            messagingStyleInformation.messages?.add(
              Message(
                input,
                DateTime.now(),
                Person(
                  key: room.client.userID,
                  name: l10n.you,
                  icon: avatarFile == null
                      ? null
                      : ByteArrayAndroidIcon(avatarFile),
                ),
              ),
            );

            await FlutterLocalNotificationsPlugin().show(
              room.id.hashCode,
              room.getLocalizedDisplayname(MatrixLocals(l10n)),
              input,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  AppConfig.pushNotificationsChannelId,
                  l10n.incomingMessages,
                  category: AndroidNotificationCategory.message,
                  shortcutId: room.id,
                  styleInformation: messagingStyleInformation,
                  groupKey: room.id,
                  playSound: false,
                  enableVibration: false,
                  actions: <AndroidNotificationAction>[
                    AndroidNotificationAction(
                      FluffyChatNotificationActions.reply.name,
                      l10n.reply,
                      inputs: [
                        AndroidNotificationActionInput(
                          label: l10n.writeAMessage,
                        ),
                      ],
                      cancelNotification: false,
                      allowGeneratedReplies: true,
                      semanticAction: SemanticAction.reply,
                    ),
                    AndroidNotificationAction(
                      FluffyChatNotificationActions.markAsRead.name,
                      l10n.markAsRead,
                      semanticAction: SemanticAction.markAsRead,
                    ),
                  ],
                ),
              ),
              payload: FluffyChatPushPayload(
                client.clientName,
                room.id,
                eventId,
              ).toString(),
            );
          }
      }
  }
}

enum FluffyChatNotificationActions { markAsRead, reply }
