import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/init_with_restore.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/push_helper.dart';

/// Shows a notification for an FCM data message on Android while the app is
/// not running, without constructing a Matrix client or opening its database.
///
/// Android has no equivalent of the iOS notification service extension, so a
/// data-only message (Sygnal's `notification_content: false`) is the only way to
/// draw an avatar, and the app has to build the notification itself.
///
/// It deliberately avoids the SDK. `Client.init` calls `clear()` on any failure,
/// which wipes the on-device database the app shares -- and a background wake is
/// exactly where failures are routine. Bootstrapping a client here logged a user
/// out on device. Everything a notification needs is already in the payload or
/// one authenticated HTTP call away, which is also how the iOS extension works.
///
/// Every failure degrades to a notification without an avatar, never to none.
class BackgroundPushNotification {
  static const _timeout = Duration(seconds: 5);

  static Future<void> show(Map<String, dynamic> data) async {
    final roomId = _string(data['room_id']);
    if (roomId == null) {
      Logs().w('[Push] Background message with no room_id; nothing to show');
      return;
    }

    // Before this handler existed, Android drew these notifications itself, so
    // a failure here must still show one. Without this, an error loading the
    // locale, the settings or the plugin posted nothing at all.
    L10n? l10n;
    try {
      l10n = await lookupL10n(PlatformDispatcher.instance.locale);
      final store = await AppSettings.init();
      final accounts = await _accounts(
        store.getStringList(ClientManager.clientNamespace) ?? const <String>[],
      );

      // With a single account there is nothing to resolve, so even a failed
      // lookup below leaves a notification that opens the right account.
      var resolved = _ResolvedPush(
        clientName: accounts.length == 1 ? accounts.single.clientName : null,
        avatar: null,
      );
      if (accounts.isNotEmpty) {
        final httpClient = http.Client();
        try {
          resolved = await _resolve(
            httpClient,
            accounts,
            roomId,
            _string(data['sender']),
          );
        } catch (e, s) {
          Logs().w('[Push] Avatar lookup failed; showing without one', e, s);
        } finally {
          httpClient.close();
        }
      }

      await _post(data, roomId, resolved.clientName, resolved.avatar, l10n);
    } catch (e, s) {
      Logs().e(
        '[Push] Background notification failed; showing a generic one',
        e,
        s,
      );
      await _postFallback(data, roomId, l10n);
    }
  }

  static Future<List<_PushAccount>> _accounts(List<String> clientNames) async {
    final accounts = <_PushAccount>[];
    for (final clientName in clientNames) {
      // One unreadable backup costs that account its avatar, not the others.
      try {
        final backup = await InitWithRestoreExtension.sessionBackupStorage.read(
          key: InitWithRestoreExtension.sessionBackupKey(clientName),
        );
        if (backup != null) {
          accounts.add(
            _PushAccount(clientName, SessionBackup.fromJsonString(backup)),
          );
        }
      } catch (e, s) {
        Logs().w('[Push] Unreadable session backup for $clientName', e, s);
      }
    }
    return accounts;
  }

  /// Resolves the account and avatar for [roomId] the same way the iOS
  /// notification service extension does.
  ///
  /// The room's avatar state comes first. Reading it also identifies the
  /// account, since the payload carries none: 200 is a member with a room
  /// avatar and 404 a member of a room without one (a direct chat). Anything
  /// else moves on to the next account: 403 is a different account or an
  /// invite not yet accepted, 401 an expired or replaced token, and a failed
  /// request proves nothing either way. An expired session fails the fallback
  /// below too, so it degrades to a notification without an avatar rather than
  /// to the wrong account.
  ///
  /// With no room avatar the sender's own avatar stands in, exactly as on iOS,
  /// and that includes invites. A profile needs no room membership, so the
  /// fallback still runs when no account could read the room.
  static Future<_ResolvedPush> _resolve(
    http.Client httpClient,
    List<_PushAccount> accounts,
    String roomId,
    String? sender,
  ) async {
    _PushAccount? member;
    String? url;
    for (final account in accounts) {
      final response = await _get(
        httpClient,
        account.session,
        '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}'
        '/state/m.room.avatar',
      );
      final status = response?.statusCode;
      if (status != 200 && status != 404) continue;
      member = account;
      if (status == 200) {
        url = _string(_json(response!.body)['url']);
      }
      break;
    }

    final session = (member ?? accounts.first).session;
    if (url == null && sender != null) {
      final response = await _get(
        httpClient,
        session,
        '/_matrix/client/v3/profile/${Uri.encodeComponent(sender)}/avatar_url',
      );
      if (response != null && response.statusCode == 200) {
        url = _string(_json(response.body)['avatar_url']);
      }
    }

    return _ResolvedPush(
      clientName:
          member?.clientName ??
          (accounts.length == 1 ? accounts.single.clientName : null),
      avatar: url == null ? null : await _download(httpClient, session, url),
    );
  }

  @visibleForTesting
  static Future<Uint8List?> avatarForTesting(
    http.Client httpClient,
    List<SessionBackup> sessions, {
    required String roomId,
    String? sender,
  }) async {
    final resolved = await _resolve(
      httpClient,
      [
        for (var i = 0; i < sessions.length; i++)
          _PushAccount('client$i', sessions[i]),
      ],
      roomId,
      sender,
    );
    return resolved.avatar;
  }

  static Future<Uint8List?> _download(
    http.Client httpClient,
    SessionBackup session,
    String url,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    if (uri.scheme == 'mxc' && uri.pathSegments.isNotEmpty) {
      final response = await _get(
        httpClient,
        session,
        '/_matrix/client/v1/media/thumbnail/${Uri.encodeComponent(uri.host)}'
        '/${Uri.encodeComponent(uri.pathSegments.first)}'
        '?width=$notificationAvatarDimension'
        '&height=$notificationAvatarDimension&method=crop',
      );
      return response != null && response.statusCode == 200
          ? response.bodyBytes
          : null;
    }

    // Not every avatar is an mxc upload (#8550). These are fetched WITHOUT the
    // access token: the allow-list includes third parties such as
    // img.youtube.com, and attaching it would leak a user's credential.
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        AppConfig.isAllowedImage(uri)) {
      try {
        final response = await httpClient.get(uri).timeout(_timeout);
        return response.statusCode == 200 ? response.bodyBytes : null;
      } catch (e) {
        Logs().w('[Push] Avatar download failed', e);
      }
    }
    return null;
  }

  static Future<http.Response?> _get(
    http.Client httpClient,
    SessionBackup session,
    String path,
  ) async {
    var homeserver = session.homeserver;
    while (homeserver.endsWith('/')) {
      homeserver = homeserver.substring(0, homeserver.length - 1);
    }
    try {
      return await httpClient
          .get(
            Uri.parse('$homeserver$path'),
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          )
          .timeout(_timeout);
    } catch (e) {
      Logs().w('[Push] Background request failed', e);
      return null;
    }
  }

  /// The notification text for a data message.
  ///
  /// A member event has no body, so an invite gets the words Sygnal used to
  /// write for it, which are also what pushHelper shows when the app is open.
  @visibleForTesting
  static String bodyFor(Map<String, dynamic> data, L10n l10n) {
    if (data['type'] == EventTypes.RoomMember &&
        data['content_membership'] == 'invite') {
      if (data['content_reason'] == 'invite_on_knock') {
        return l10n.knockAccepted;
      }
      final inviter =
          _string(data['sender_display_name']) ?? _string(data['sender']);
      if (inviter != null) return l10n.youInvitedBy(inviter);
    }
    return _string(data['content_body']) ?? l10n.openAppToReadMessages;
  }

  static Future<FlutterLocalNotificationsPlugin> _plugin() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/notification_icon'),
      ),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    return plugin;
  }

  /// Carries every string field of the message, so a tap routes exactly as it
  /// did when Android drew the notification: a course ping to its activity
  /// session, a check-in to its analytics.
  static String _payload(
    Map<String, dynamic> data,
    String roomId,
    String? clientName,
  ) => FluffyChatPushPayload(
    clientName,
    roomId,
    _string(data['event_id']),
    additionalData: {
      for (final entry in data.entries)
        if (entry.value is String) entry.key: entry.value as String,
    },
  ).toString();

  static Future<void> _postFallback(
    Map<String, dynamic> data,
    String roomId,
    L10n? l10n,
  ) async {
    try {
      l10n ??= await lookupL10n(const Locale('en'));
      final plugin = await _plugin();
      await plugin.show(
        roomId.hashCode,
        l10n.newMessageInPangeaChat,
        l10n.openAppToReadMessages,
        NotificationDetails(
          android: AndroidNotificationDetails(
            AppConfig.pushNotificationsChannelId,
            l10n.incomingMessages,
            importance: Importance.high,
            priority: Priority.max,
            shortcutId: roomId,
          ),
        ),
        payload: _payload(data, roomId, null),
      );
    } catch (e, s) {
      Logs().e('[Push] Fallback notification also failed', e, s);
    }
  }

  static Future<void> _post(
    Map<String, dynamic> data,
    String roomId,
    String? clientName,
    Uint8List? avatar,
    L10n l10n,
  ) async {
    final plugin = await _plugin();

    final roomName = _string(data['room_name']);
    final senderName =
        _string(data['sender_display_name']) ??
        _string(data['sender']) ??
        l10n.newMessageInPangeaChat;
    final body = bodyFor(data, l10n);
    final icon = avatar == null ? null : ByteArrayAndroidIcon(avatar);
    final id = roomId.hashCode;

    final message = Message(
      body,
      DateTime.now(),
      Person(key: _string(data['sender']), name: senderName, icon: icon),
    );

    // Consecutive messages in one room stack rather than replace each other,
    // as they do when pushHelper draws them.
    final existing = await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.getActiveNotificationMessagingStyle(id);
    existing?.messages?.add(message);

    // Sygnal only sends room_name for a named room, so its absence is the best
    // signal available without the SDK that this is a direct chat.
    final isDirectChat = roomName == null;

    await plugin.show(
      id,
      roomName ?? senderName,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          AppConfig.pushNotificationsChannelId,
          l10n.incomingMessages,
          number: int.tryParse(_string(data['unread']) ?? ''),
          category: AndroidNotificationCategory.message,
          shortcutId: roomId,
          // The same as pushHelper. Android creates the channel from the first
          // notification posted to it and never updates it, so a lower
          // importance here would stop every later notification from popping up.
          importance: Importance.high,
          priority: Priority.max,
          styleInformation:
              existing ??
              MessagingStyleInformation(
                Person(name: senderName, icon: icon, key: roomId),
                conversationTitle: isDirectChat ? null : roomName,
                groupConversation: !isDirectChat,
                messages: [message],
              ),
        ),
      ),
      payload: _payload(data, roomId, clientName),
    );
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static Map<String, Object?> _json(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }
}

class _PushAccount {
  final String clientName;
  final SessionBackup session;

  const _PushAccount(this.clientName, this.session);
}

class _ResolvedPush {
  final String? clientName;
  final Uint8List? avatar;

  const _ResolvedPush({required this.clientName, required this.avatar});
}
