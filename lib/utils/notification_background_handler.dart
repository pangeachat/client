import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/dosage/dosage_message_signals.dart';
import 'package:fluffychat/features/notifications/notification_tap_utils.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/push_helper.dart';
import '../config/app_config.dart';
import '../config/setting_keys.dart';

bool _vodInitialized = false;

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
  final clients = await ClientManager.getClients(
    initialize: false,
    store: store,
  );
  // Select the account the notification is FOR — its payload carries the
  // clientName — by EXACT match only. Never fall back to the first (or sole)
  // client: a stale notification for a logged-out account A must not be sent (or
  // dosage-attributed) as the remaining account B when B happens to know the
  // room. A missing/blank/mismatched clientName is ignored rather than acting as
  // another account.
  final payloadClientName = FluffyChatPushPayload.fromString(
    notificationResponse.payload ?? '',
  ).clientName;
  final client = (payloadClientName == null || payloadClientName.isEmpty)
      ? null
      : clients.firstWhereOrNull((c) => c.clientName == payloadClientName);
  if (client == null) {
    Logs().w(
      'Notification tap for unknown/mismatched account "$payloadClientName"; '
      'ignoring rather than acting as another account.',
    );
    IsolateNameServer.removePortNameMapping(AppConfig.pushIsolatePortName);
    return;
  }
  await client.abortSync();
  await client.init(
    waitForFirstSync: false,
    waitUntilLoadCompletedLoaded: false,
  );

  if (!client.isLogged()) {
    throw Exception('Notification tab in background but not logged in!');
  }
  try {
    await notificationTap(
      notificationResponse,
      client: client,
      background: true,
    );
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
  // True only on the vm:entry-point background isolate (main isolate down),
  // which disposes its client the instant this returns. It changes ONLY the
  // dosage emit: background AWAITS an envelope-only POST (so it lands before
  // teardown); the main isolate fire-and-forgets the normal envelope +
  // engagement tick (its analytics lifecycle flushes the span) and is never
  // delayed by the POST.
  bool background = false,
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

      // #Pangea
      // if (router == null) {
      //   Logs().v('Ignore select notification action in background mode');
      //   return;
      // }
      // Logs().v('Open room from notification tap', roomId);
      // await client.roomsLoading;
      // await client.accountDataLoading;
      // if (client.getRoomById(roomId) == null) {
      //   await client
      //       .waitForRoomInSync(roomId)
      //       .timeout(const Duration(seconds: 30));
      // }
      // router.go(
      //   client.getRoomById(roomId)?.membership == Membership.invite
      //       ? '/rooms'
      //       : '/rooms/$roomId',
      // );
      await NotificationTapUtil.handleNotificationTap(
        client: client,
        roomId: roomId,
        notification: payload.additionalData,
        router: router,
      );
    // Pangea#
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

          // A notification quick-reply is a genuine learner text turn, so it
          // emits dosage signals once the event id resolves. Load the dosage env
          // into this isolate first: the background notification isolate boots
          // without `.env`, so without this the emit would read the flags as
          // unloaded and no-op. Idempotent in the main isolate; best-effort,
          // never blocks the reply. When the flags are off (or uninitialised),
          // the repo gate no-ops WITHOUT throwing.
          await DosageMessageSignals.ensureDosageEnvLoaded();
          if (background) {
            // Background isolate: it disposes its client in the `finally` right
            // after this returns, so a fire-and-forget emit would be dropped.
            // AWAIT an envelope-only POST (bounded, swallowed); the isolate has
            // no lifecycle to flush an engagement span.
            await DosageMessageSignals.emitReplyEnvelope(
              roomId: room.id,
              accessToken: room.client.accessToken,
              msgEventId: eventId,
              body: input,
            );
          } else {
            // Main isolate: fire-and-forget the normal envelope + engagement
            // tick (the analytics lifecycle flushes the span). Do NOT await —
            // the notification flow must not wait on a telemetry POST.
            DosageMessageSignals.emitForSentMessage(
              roomId: room.id,
              userId: room.client.userID,
              deviceId: room.client.deviceID,
              accessToken: room.client.accessToken,
              msgEventId: eventId,
              body: input,
            );
          }

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
