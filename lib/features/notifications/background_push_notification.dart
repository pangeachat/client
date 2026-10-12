import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:pangea_call_capture/pangea_call_capture.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
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
      final single = accounts.length == 1 ? accounts.single : null;
      var resolved = _ResolvedPush(
        clientName: single?.clientName,
        avatar: null,
        session: single?.session,
      );
      final eventId = _string(data['event_id']);
      IncomingRing? ring;
      if (accounts.isNotEmpty) {
        final httpClient = http.Client();
        try {
          final isRing = data['type'] == PangeaEventTypes.callNotification;
          resolved = await _resolve(
            httpClient,
            accounts,
            roomId,
            _string(data['sender']),
            // A ring has to start within the few seconds Android allows a
            // push to start one, and the ringing notification draws no
            // avatar, so it does not wait on one.
            withAvatar: !isRing,
          );
          final session = resolved.session;
          if (isRing && session != null && eventId != null) {
            ring = await _ring(httpClient, session, roomId, eventId);
            if (ring != null &&
                await _ringAndWatch(
                  session,
                  ring,
                  roomId,
                  _payload(data, roomId, resolved.clientName),
                  caller: _string(data['sender_display_name']),
                  channelName: l10n.callIncoming,
                )) {
              return;
            }
          }
        } catch (e, s) {
          Logs().w('[Push] Avatar lookup failed; showing without one', e, s);
        } finally {
          httpClient.close();
        }
      }

      // Reached by a ring only when it could not be read, or the phone would
      // not ring for it. It still shows: missing a call someone is waiting on
      // costs more than a notice for one that has just ended.
      await _post(
        data,
        roomId,
        resolved.clientName,
        resolved.avatar,
        l10n,
        ring,
      );
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
    String? sender, {
    bool withAvatar = true,
  }) async {
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
    if (withAvatar && url == null && sender != null) {
      final response = await _get(
        httpClient,
        session,
        '/_matrix/client/v3/profile/${Uri.encodeComponent(sender)}/avatar_url',
      );
      if (response != null && response.statusCode == 200) {
        url = _string(_json(response.body)['avatar_url']);
      }
    }

    final single = accounts.length == 1 ? accounts.single : null;
    return _ResolvedPush(
      clientName: member?.clientName ?? single?.clientName,
      avatar: !withAvatar || url == null
          ? null
          : await _download(httpClient, session, url),
      session: member?.session ?? single?.session,
    );
  }

  /// The ring a push announces, read from the homeserver, or null when it
  /// could not be read.
  ///
  /// The payload cannot answer whether it still rings: Sygnal copies only the
  /// top-level text fields of an event's content into it, and a ring's
  /// lifetime and the call it names are nested.
  static Future<IncomingRing?> _ring(
    http.Client httpClient,
    SessionBackup session,
    String roomId,
    String eventId,
  ) async {
    final response = await _get(
      httpClient,
      session,
      '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}'
      '/event/${Uri.encodeComponent(eventId)}',
    );
    if (response == null || response.statusCode != 200) {
      Logs().w('[Push] Could not read ring $eventId: ${response?.statusCode}');
      return null;
    }
    try {
      return IncomingRing(
        event: MatrixEvent.fromJson(_json(response.body)),
        myUserId: session.userId,
        // A closed app is in no call.
        alreadyJoined: false,
      );
    } catch (e, s) {
      Logs().w('[Push] Could not parse ring $eventId', e, s);
      return null;
    }
  }

  @visibleForTesting
  static Future<IncomingRing?> ringForTesting(
    http.Client httpClient,
    SessionBackup session, {
    required String roomId,
    required String eventId,
  }) => _ring(httpClient, session, roomId, eventId);

  /// How often a ringing phone checks whether the call still wants it.
  static const _watchEvery = Duration(seconds: 2);

  /// Rings for [ring] and watches it as the banner would.
  ///
  /// True when nothing more should be shown: the phone is ringing, or the
  /// call no longer wants it. False when the platform would not ring, and an
  /// ordinary notification has to say it instead.
  ///
  /// Returns once ringing has started. The watch goes on until the phone has
  /// stopped, handed to [watching], and is not awaited by default: the push
  /// handler runs one message at a time, so a ring watched to its end would
  /// hold every other notification behind it for as long as it rang.
  static Future<bool> _ringAndWatch(
    SessionBackup session,
    IncomingRing ring,
    String roomId,
    String payload, {
    required String? caller,
    required String channelName,
    http.Client? httpClient,
    IncomingCallRinger ringer = const IncomingCallRinger(),
    Duration every = _watchEvery,
    void Function(Future<void> watched) watching = unawaited,
  }) async {
    final ringId = ring.event.eventId;
    if (!ring.shouldRing(DateTime.now())) {
      Logs().i('[Push] Ring $ringId no longer rings here; not showing it');
      return true;
    }
    // The watch outlives the push that started it, so it has its own client.
    final client = httpClient ?? http.Client();
    void release() {
      if (httpClient == null) client.close();
    }

    final watch = _RingWatch(client, session, ring, roomId);
    // Asked before ringing as well as during. A ring read back after the
    // caller gave up, or after another device answered, is a call that is
    // already over -- the rule the app applies to a ring it missed.
    if (await watch.over()) {
      release();
      return true;
    }
    try {
      final rang = await ringer.ring(
        ringId: ringId,
        caller: caller ?? ring.event.senderId,
        video: ring.isVideo,
        expiresAt: ring.expiresAt,
        channelName: channelName,
        payload: payload,
      );
      if (!rang) {
        Logs().w('[Push] The platform would not ring for $ringId');
        release();
        return false;
      }
    } catch (e, s) {
      Logs().w('[Push] Could not ring for $ringId', e, s);
      release();
      return false;
    }
    watching(() async {
      try {
        await watch.until(ringer, every);
      } catch (e, s) {
        // The ring stops either way: a phone that can no longer tell whether
        // the call wants it must not go on ringing for one taken elsewhere.
        Logs().e('[Push] Stopped watching ring $ringId', e, s);
        await ringer.stop(ringId).catchError((Object e, StackTrace s) {
          Logs().e('[Push] Could not stop ring $ringId', e, s);
        });
      } finally {
        release();
      }
    }());
    return true;
  }

  @visibleForTesting
  static Future<bool> ringAndWatchForTesting(
    http.Client httpClient,
    SessionBackup session,
    IncomingRing ring, {
    required String roomId,
    required IncomingCallRinger ringer,
    required Duration every,
  }) async {
    Future<void>? watched;
    final handled = await _ringAndWatch(
      session,
      ring,
      roomId,
      'payload',
      caller: 'Teacher',
      channelName: 'Incoming call',
      httpClient: httpClient,
      ringer: ringer,
      every: every,
      watching: (watch) => watched = watch,
    );
    await watched;
    return handled;
  }

  static Future<http.Response?> _put(
    http.Client httpClient,
    SessionBackup session,
    String path,
    Map<String, Object?> body,
  ) async {
    var homeserver = session.homeserver;
    while (homeserver.endsWith('/')) {
      homeserver = homeserver.substring(0, homeserver.length - 1);
    }
    try {
      return await httpClient
          .put(
            Uri.parse('$homeserver$path'),
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (e) {
      Logs().w('[Push] Background request failed', e);
      return null;
    }
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
  /// A ring has none either, and says what kind of call it is when [ring]
  /// could be read.
  @visibleForTesting
  static String bodyFor(
    Map<String, dynamic> data,
    L10n l10n, [
    IncomingRing? ring,
  ]) {
    if (data['type'] == PangeaEventTypes.callNotification) {
      if (ring == null) return l10n.callIncoming;
      return ring.isVideo ? l10n.callIncomingVideo : l10n.callIncomingVoice;
    }
    // Only a missed call's card pushes. Its own text is the caller's, in the
    // caller's words; this says it from the learner's side, in theirs.
    if (data['type'] == PangeaEventTypes.call) {
      return l10n.callHistoryMissedCall;
    }
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
    IncomingRing? ring,
  ) async {
    final plugin = await _plugin();

    final roomName = _string(data['room_name']);
    final senderName =
        _string(data['sender_display_name']) ??
        _string(data['sender']) ??
        l10n.newMessageInPangeaChat;
    final body = bodyFor(data, l10n, ring);
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
          // A missed call replaces a ring that has just stopped; chiming for
          // it as well would be a second alert for the same call.
          silent: data['type'] == PangeaEventTypes.call,
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

/// Whether a ring still wants this phone, read from the server while it rings.
///
/// The questions are the banner's -- has the caller given up, has another of
/// this learner's devices answered or declined -- asked through the same
/// rules in [CallService], over state fetched by hand: the closed app has no
/// Matrix client to keep it. A read that fails says nothing, and the phone
/// goes on ringing; the ring's own lifetime bounds that.
class _RingWatch {
  final http.Client httpClient;
  final SessionBackup session;
  final IncomingRing ring;
  final String roomId;

  _RingWatch(this.httpClient, this.session, this.ring, this.roomId);

  /// Whether the caller has been seen in the call. A caller who was there and
  /// is no longer has given up.
  bool _callerSeen = false;

  String get _ringId => ring.event.eventId;

  String get _room => Uri.encodeComponent(roomId);

  /// Whether the call no longer wants this phone.
  Future<bool> over() async {
    final states = await _memberStates();
    if (states != null) {
      if (CallService.answeredElsewhereIn(
        states,
        me: session.userId,
        // This phone has not joined, so any membership of ours written after
        // the ring is another device's.
        myDevice: session.deviceId ?? '',
        ringSentAt: ring.orderedAt,
        now: DateTime.now(),
      )) {
        Logs().i('[Push] Ring $_ringId was answered on another device');
        return true;
      }
      final presence = CallService.presenceIn(
        states,
        ring.event.senderId,
        deviceId: ring.senderDeviceId,
      );
      if (presence == PeerPresence.live) {
        _callerSeen = true;
      } else if (presence == PeerPresence.gone || _callerSeen) {
        // The server's state is complete, unlike a client's still syncing, so
        // a retraction read here is the caller leaving, not state yet to come.
        Logs().i('[Push] The caller of $_ringId has given up');
        return true;
      }
    }
    if (await _declinedElsewhere()) {
      Logs().i('[Push] Ring $_ringId was declined on another device');
      return true;
    }
    return false;
  }

  /// Watches until the ring ends, then makes sure the phone has stopped.
  Future<void> until(IncomingCallRinger ringer, Duration every) async {
    while (DateTime.now().isBefore(ring.expiresAt)) {
      await Future<void>.delayed(every);
      switch (await ringer.outcome(_ringId)) {
        case RingOutcome.declined:
          await _decline();
          return;
        case RingOutcome.ringing:
          if (await over()) {
            await ringer.stop(_ringId);
            return;
          }
        case RingOutcome.answered:
        case RingOutcome.ended:
        case RingOutcome.failed:
        case null:
          // Answered: the app has the call now. Otherwise the ring is over.
          return;
      }
    }
    await ringer.stop(_ringId);
  }

  Future<List<MatrixEvent>?> _memberStates() async {
    final response = await BackgroundPushNotification._get(
      httpClient,
      session,
      '/_matrix/client/v3/rooms/$_room/state',
    );
    if (response == null || response.statusCode != 200) {
      Logs().w('[Push] Could not read call state: ${response?.statusCode}');
      return null;
    }
    try {
      return [
        for (final json in jsonDecode(response.body) as List)
          if (json is Map<String, Object?> &&
              json['type'] == EventTypes.GroupCallMember)
            MatrixEvent.fromJson(json),
      ];
    } catch (e, s) {
      Logs().w('[Push] Could not parse call state', e, s);
      return null;
    }
  }

  Future<bool> _declinedElsewhere() async {
    final filter = jsonEncode({
      'types': [PangeaEventTypes.callDecline],
      'senders': [session.userId],
    });
    final response = await BackgroundPushNotification._get(
      httpClient,
      session,
      '/_matrix/client/v3/rooms/$_room/messages'
      '?dir=b&limit=20&filter=${Uri.encodeComponent(filter)}',
    );
    if (response == null || response.statusCode != 200) {
      Logs().w('[Push] Could not read declines: ${response?.statusCode}');
      return false;
    }
    try {
      final chunk = (jsonDecode(response.body) as Map)['chunk'] as List;
      return chunk.any(
        (json) =>
            json is Map<String, Object?> &&
            json['sender'] == session.userId &&
            CallService.declineTargetOf(MatrixEvent.fromJson(json)) == _ringId,
      );
    } catch (e, s) {
      Logs().w('[Push] Could not parse declines', e, s);
      return false;
    }
  }

  /// Tells the caller the learner declined from the notification, so their
  /// phone stops ringing too.
  Future<void> _decline() async {
    final txnId = 'ring-decline-${DateTime.now().microsecondsSinceEpoch}';
    final response = await BackgroundPushNotification._put(
      httpClient,
      session,
      '/_matrix/client/v3/rooms/$_room/send'
      '/${Uri.encodeComponent(PangeaEventTypes.callDecline)}/$txnId',
      CallService.declineContent(_ringId),
    );
    if (response == null || response.statusCode != 200) {
      // The caller rings out instead, and their history reads unanswered.
      Logs().w('[Push] Could not send the decline: ${response?.statusCode}');
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

  /// The account that can read the room, used to read a ring back.
  final SessionBackup? session;

  const _ResolvedPush({
    required this.clientName,
    required this.avatar,
    required this.session,
  });
}
