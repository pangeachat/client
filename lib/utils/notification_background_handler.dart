import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/notifications/notification_tap_utils.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_manager.dart';
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

  // One encompassing try/finally: EVERY exit (including an ignored mismatch or a
  // thrown error) must dispose the temporary clients this isolate created, send
  // DONE, and remove the port mapping — otherwise a bare `return` leaks them.
  List<Client> clients = const [];
  try {
    if (!_vodInitialized) {
      await vod.init();
      _vodInitialized = true;
    }
    final store = await AppSettings.init();
    clients = await ClientManager.getClients(initialize: false, store: store);
    // Select the account the notification is FOR — its payload carries the
    // clientName — by EXACT match only. Never fall back to the first (or sole)
    // client: a stale notification for a logged-out account A must not be sent
    // (or dosage-attributed) as the remaining account B when B happens to know
    // the room. A missing/blank/mismatched clientName is ignored rather than
    // acting as another account.
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
    await notificationTap(
      notificationResponse,
      client: client,
      background: true,
    );
  } finally {
    for (final c in clients) {
      try {
        await c.dispose(closeDatabase: false);
      } catch (_) {}
    }
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
        // A notification shown before an action was removed (e.g. the Android
        // reply action, #9340) can still carry it until it is dismissed.
        throw Exception(
          'Selected notification with unknown action ${notificationResponse.actionId}',
        );
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
      }
  }
}

enum FluffyChatNotificationActions { markAsRead }
