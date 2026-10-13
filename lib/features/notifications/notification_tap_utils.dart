import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_consent_handler.dart';
import 'package:fluffychat/features/bot/bot_event_extension.dart';
import 'package:fluffychat/features/bot/bot_room_extension.dart';
import 'package:fluffychat/features/bot/bot_target_event_name_enum.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/pangea/common/utils/named_timeout.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_constants.dart';
import 'package:fluffychat/routes/chat_list/chat_invite_dialog.dart';
import 'package:fluffychat/utils/chat_list_handle_space_tap.dart';

class NotificationTapUtil {
  static const _sessionIdKey =
      'content_${CoursePingConstants.coursePingRoomId}';
  static const _activityIdKey =
      'content_${CoursePingConstants.coursePingActivityId}';

  static const _targetEventKey = 'content_pangea.analytics.target_event_name';
  static const _variantKey = 'content_pangea.analytics.variant';
  static const _chatIdKey = 'content_pangea.analytics.target_param.chat_id';
  static const _groupIdKey = 'content_pangea.analytics.target_param.group_id';
  static const _botActivityIdKey =
      'content_pangea.analytics.target_param.activity_id';
  static const _roomIdKey = 'content_pangea.analytics.target_param.room_id';
  static const _actionKey = 'content_pangea.analytics.target_param.action';
  static const _nameKey = 'content_pangea.analytics.target_param.name';
  static const _checkInTypeKey =
      'content_${BotEventExtension.noticeCheckInTypeKey}';
  static const _destinationPathKey =
      'content_${BotEventExtension.noticeDestinationPathKey}';

  static Future<void> _ensureRoomLoaded(Client client, String roomId) async {
    await client.roomsLoading;
    await client.accountDataLoading;
    if (client.getRoomById(roomId) == null) {
      await client
          .waitForRoomInSync(roomId)
          .timeoutNamed(
            const Duration(seconds: 30),
            'waitForRoomInSync: notification tap',
          );
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
    try {
      final parameters = botNotificationOpenedParameters(notification);
      if (parameters != null) GoogleAnalytics.openBotNotification(parameters);
    } catch (err, s) {
      ErrorHandler.logError(e: err, s: s, data: {'notification': notification});
    }
  }

  /// The `bot_notification_opened` parameters for a tapped notice, or null
  /// when it carries neither a variant nor a known product action. An open is
  /// counted by its variant; the product action rides along only when the
  /// notice's goal names one, and an unknown one is reported and left off
  /// rather than dropping the open (the notice content contract in the
  /// engagement repo's analytics.instructions.md).
  @visibleForTesting
  static Map<String, String>? botNotificationOpenedParameters(
    Map<String, dynamic> notification,
  ) {
    String? read(String key) {
      final value = notification[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final targetEventNameEntry = read(_targetEventKey);
    final targetEventName = BotTargetEventName.values.firstWhereOrNull(
      (e) => e.name == targetEventNameEntry,
    );
    if (targetEventNameEntry != null && targetEventName == null) {
      ErrorHandler.logError(
        e: Exception('Unknown BotTargetEventName: $targetEventNameEntry'),
        data: {'targetEventNameEntry': targetEventNameEntry},
      );
    }

    final variant = read(_variantKey);
    if (variant == null && targetEventName == null) return null;
    return {
      'target_event_name': ?targetEventName?.name,
      'variant': ?variant,
      'notification_type': ?read(_checkInTypeKey),
      'chat_id': ?read(_chatIdKey),
      'group_id': ?read(_groupIdKey),
      'activity_id': ?read(_botActivityIdKey),
      'room_id': ?read(_roomIdKey),
      'action': ?read(_actionKey),
      'name': ?read(_nameKey),
    };
  }

  /// A course ping is posted in its course, so its activity opens there; a
  /// notice names no course, so its activity opens with none.
  static void _navigateToActivitySession({
    required GoRouter router,
    required Room room,
    required String sessionRoomId,
    required String activityId,
  }) {
    try {
      router.go(
        room.client.activitySessionLocation(
          router.routeInformationProvider.value.uri,
          courseRoomId: room.isSpace ? room.id : null,
          sessionRoomId: sessionRoomId,
          activityId: activityId,
        ),
      );
    } catch (err, s) {
      ErrorHandler.logError(e: err, s: s, data: {'roomId': sessionRoomId});
    }
  }

  /// The notice's app path, when it may be followed: only from a notice the
  /// bot sent into the bot DM, because some paths do more than open a page (a
  /// join-code link submits the join) and anyone can put the key in an event.
  static String? _botDestinationPath(
    Room room,
    Map<String, dynamic>? notification,
  ) {
    final path = notification?[_destinationPathKey];
    if (path is! String || path.isEmpty) return null;
    final fromBot =
        room.isBotDM && notification?['sender'] == BotName.byEnvironment;
    if (fromBot && PRoutes.isAppPath(path)) return path;
    ErrorHandler.logError(
      e: Exception(
        fromBot
            ? 'Notice destination is not an app path'
            : 'Notice destination path not sent by the bot in its DM',
      ),
      data: {'roomId': room.id, 'eventId': notification?['event_id']},
    );
    return null;
  }

  /// The Open button on a notice in the bot DM: the same opened record and
  /// the same destination as tapping the notice's push.
  static Future<void> openNotice(Event notice, GoRouter router) =>
      handleNotificationTap(
        client: notice.room.client,
        roomId: notice.room.id,
        notification: notificationDataFor(notice),
        router: router,
      );

  /// [notice] in the shape its push arrives in: the push gateway puts each
  /// event content key under a `content_` prefix.
  @visibleForTesting
  static Map<String, dynamic> notificationDataFor(Event notice) => {
    'event_id': notice.eventId,
    'room_id': notice.room.id,
    'sender': notice.senderId,
    'type': notice.type,
    for (final entry in notice.content.entries)
      'content_${entry.key}': entry.value,
  };

  /// Answers an invite in the prompt the app uses for that kind of room, never
  /// by opening the room: the chat view joins an invited room as it builds,
  /// which would accept the invite without asking.
  static Future<void> _answerInvite(GoRouter router, Room room) async {
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context == null) {
      ErrorHandler.logError(
        e: Exception('No navigator to prompt for a tapped invite'),
        data: {'roomId': room.id},
      );
      return;
    }

    if (room.isSpace) {
      // The course prompt opens the course itself once accepted; a response
      // here means the invite was accepted without asking.
      final joinResp = await SpaceTapUtil.onInviteTap(context, room);
      if (joinResp == null || !context.mounted) return;
      final joinedRoomId = await JoinRoomAnalyticsConsentHandler(
        joinResp,
        room,
      ).handle(context);
      if (joinedRoomId == null) return;
      router.go(
        WorkspaceNav.openCourse(
          router.routeInformationProvider.value.uri,
          joinedRoomId,
        ),
      );
      return;
    }

    if (await ChatInviteDialog.show(context, room)) {
      router.go(
        WorkspaceNav.openRoomById(
          router.routeInformationProvider.value.uri,
          room.id,
        ),
      );
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

    final uri = router.routeInformationProvider.value.uri;

    final sessionRoomId = notification?[_sessionIdKey] as String?;
    final activityId = notification?[_activityIdKey] as String?;

    if (sessionRoomId != null &&
        sessionRoomId.isNotEmpty &&
        activityId != null &&
        activityId.isNotEmpty) {
      _navigateToActivitySession(
        router: router,
        room: room,
        sessionRoomId: sessionRoomId,
        activityId: activityId,
      );
      return;
    }

    final destinationPath = _botDestinationPath(room, notification);
    if (destinationPath != null) {
      router.go(destinationPath);
      return;
    }

    // An analytics room is an internal construct store, never a chat surface
    // (#8268). Instructors are auto-joined to student analytics rooms, so the
    // invite branch below never catches this — fail fast to the joined parent
    // course (or the map) instead of relying on the room panel to reject it.
    if (room.isAnalyticsRoom) {
      final parentCourseId = room.pangeaSpaceParents
          .firstWhereOrNull((p) => p.membership == Membership.join)
          ?.id;
      router.go(
        parentCourseId != null
            ? WorkspaceNav.openCourse(uri, parentCourseId)
            : PRoutes.world,
      );
      return;
    }

    // An invite to an activity session opens its activity page with the
    // session bound, not the room: the chat view joins an invited room as it
    // builds, and the start page's role picker is where the invitee accepts.
    // No course context is forced open (joining-courses.instructions.md).
    final invitedActivityId = room.membership == Membership.invite
        ? room.activityId
        : null;
    if (invitedActivityId != null) {
      router.go(
        client.activitySessionLocation(
          uri,
          sessionRoomId: roomId,
          activityId: invitedActivityId,
        ),
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
        router.go(WorkspaceNav.openCourse(uri, parentCourseId));
        return;
      }
    }

    if (room.membership == Membership.invite) {
      await _answerInvite(router, room);
    } else if (room.isSpace == true) {
      router.go(WorkspaceNav.openCourse(uri, roomId));
    } else {
      router.go(WorkspaceNav.openRoomById(uri, roomId));
    }
  }
}

extension ActivitySessionLocationClientExtension on Client {
  /// Where a pointer to an activity session opens: the session itself once
  /// this user has joined it, otherwise the activity with the session bound,
  /// in [courseRoomId] when there is one.
  String activitySessionLocation(
    Uri current, {
    String? courseRoomId,
    required String sessionRoomId,
    required String activityId,
  }) {
    final session = getRoomById(sessionRoomId);
    // Pings sent before #8138 carry the course space id instead of the
    // session room id, so a space here falls through to the activity page.
    if (session != null &&
        !session.isSpace &&
        session.membership == Membership.join) {
      return WorkspaceNav.openRoomById(current, sessionRoomId);
    }
    if (courseRoomId == null) {
      return WorkspaceNav.setLeft(current, [
        ActivityPanelToken(
          ActivityTokenParam(activityId: activityId, roomId: sessionRoomId),
        ),
      ]);
    }
    return WorkspaceNav.openCourseActivity(
      courseRoomId,
      activityId,
      roomId: sessionRoomId,
    );
  }
}
