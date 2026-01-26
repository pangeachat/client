import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:desktop_notifications/desktop_notifications.dart';
import 'package:matrix/matrix.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

extension LocalNotificationsExtension on MatrixState {
  static final html.AudioElement _audioPlayer = html.AudioElement()
    ..src = 'assets/assets/sounds/notification.ogg'
    ..load();

  void showLocalNotification(Event event) async {
    final roomId = event.room.id;
    if (activeRoomId == roomId) {
      if (kIsWeb && webHasFocus) return;
      if (PlatformInfos.isDesktop &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
    }

    final title =
        event.room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final body = await event.calcLocalizedBody(
      MatrixLocals(L10n.of(context)),
      withSenderNamePrefix: !event.room.isDirectChat ||
          event.room.lastEvent?.senderId == client.userID,
      plaintextBody: true,
      hideReply: true,
      hideEdit: true,
      removeMarkdown: true,
    );

    if (kIsWeb) {
      // #Pangea
      if (html.Notification.permission != 'granted') return;
      // Pangea#
      final avatarUrl = event.senderFromMemoryOrFallback.avatarUrl;
      Uri? thumbnailUri;

      if (avatarUrl != null) {
        const size = 64;
        const thumbnailMethod = ThumbnailMethod.crop;
        // Pre-cache so that we can later just set the thumbnail uri as icon:
        await client.downloadMxcCached(
          avatarUrl,
          width: size,
          height: size,
          thumbnailMethod: thumbnailMethod,
          isThumbnail: true,
        );

        thumbnailUri =
            await event.senderFromMemoryOrFallback.avatarUrl?.getThumbnailUri(
          client,
          width: size,
          height: size,
          method: thumbnailMethod,
        );
      }

      // #Pangea
      _audioPlayer.volume = AppConfig.volume;
      // Pangea#
      _audioPlayer.play();

      html.Notification(
        title,
        body: body,
        icon: thumbnailUri?.toString(),
        tag: event.room.id,
      );
    } else if (Platform.isLinux) {
      final notification = await linuxNotifications!.notify(
        title,
        body: body,
        replacesId: linuxNotificationIds[roomId] ?? 0,
        appName: AppConfig.applicationName,
        appIcon: 'fluffychat',
        actions: [
          NotificationAction(
            DesktopNotificationActions.openChat.name,
            L10n.of(context).openChat,
          ),
          NotificationAction(
            DesktopNotificationActions.seen.name,
            L10n.of(context).markAsRead,
          ),
        ],
        hints: [
          NotificationHint.soundName('message-new-instant'),
        ],
      );
      notification.action.then((actionStr) {
        var action = DesktopNotificationActions.values
            .singleWhereOrNull((a) => a.name == actionStr);
        if (action == null && actionStr == "default") {
          action = DesktopNotificationActions.openChat;
        }
        switch (action!) {
          case DesktopNotificationActions.seen:
            event.room.setReadMarker(
              event.eventId,
              mRead: event.eventId,
              public: AppConfig.sendPublicReadReceipts,
            );
            break;
          case DesktopNotificationActions.openChat:
            FluffyChatApp.router.go('/rooms/${event.room.id}');
            break;
        }
      });
      linuxNotificationIds[roomId] = notification.id;
    }
  }

  // #Pangea
  Future<bool> get notificationsEnabled {
    return kIsWeb
        ? Future.value(html.Notification.permission == 'granted')
        : Permission.notification.isGranted;
  }

  Future<void> requestPermission() async {
    if (kIsWeb) {
      await html.Notification.requestPermission();
    } else {
      final status = await Permission.notification.request();
      if (status.isGranted) {
        // Notification permissions granted
      } else if (status.isDenied) {
        // Notification permissions denied
      } else if (status.isPermanentlyDenied) {
        // Notification permissions permanently denied, open app settings
        await openAppSettings();
      }
    }

    notifPermissionNotifier.value = notifPermissionNotifier.value + 1;
  }
  // Pangea#
}

enum DesktopNotificationActions { seen, openChat }
