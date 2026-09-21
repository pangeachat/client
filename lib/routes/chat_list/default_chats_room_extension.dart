import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/named_timeout.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat_list/course_chats_settings_model.dart';
import 'package:fluffychat/routes/chat_list/course_default_chats_enum.dart';
import 'package:fluffychat/routes/chat_list/course_hierarchy_extension.dart';

extension DefaultChatsRoomExtension on Room {
  CourseChatsSettingsModel get courseChatsSettings {
    final event = getState(PangeaEventTypes.courseChatList);
    if (event == null) {
      return const CourseChatsSettingsModel();
    }
    return CourseChatsSettingsModel.fromJson(event.content);
  }

  Future<void> setCourseChatsSettings(CourseChatsSettingsModel settings) async {
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.courseChatList,
      "",
      settings.toJson(),
    );
  }

  CourseDefaultChatsEnum? get defaultChatType =>
      CourseDefaultChatsEnum.values.firstWhereOrNull(
        (type) => canonicalAlias.localpart?.startsWith(type.alias) == true,
      );

  bool isDefaultChatByType(CourseDefaultChatsEnum type) =>
      canonicalAlias.localpart?.startsWith(type.alias) == true;

  bool hasDefaultChat(CourseDefaultChatsEnum type) =>
      pangeaSpaceChildren.any((r) => r.isDefaultChatByType(type));

  /// Joins the course's default chats (introductions, announcements) that
  /// exist but this user has not joined yet. Runs when the course page opens,
  /// so a member is in them without having to go looking for them (#9031).
  ///
  /// The space hierarchy is what this needs: an unjoined child is not in
  /// `client.rooms`, and its canonical alias is the only thing marking it as
  /// a default chat.
  Future<void> joinDefaultChats() async {
    final missing = CourseDefaultChatsEnum.values
        .where((type) => !hasDefaultChat(type))
        .toSet();
    if (missing.isEmpty) return;

    // The default chats are not guaranteed to be on the hierarchy's first
    // page, so read on until both are found.
    try {
      await for (final chunk in hierarchyChildren()) {
        final alias = chunk.canonicalAlias;
        if (alias == null) continue;

        final type = missing.firstWhereOrNull(
          (type) => alias.localpart?.startsWith(type.alias) == true,
        );
        if (type == null) continue;
        missing.remove(type);

        try {
          await client.joinRoom(alias);
        } catch (e, s) {
          ErrorHandler.logError(
            e: e,
            s: s,
            data: {'alias': alias, 'spaceId': id},
          );
        }
        if (missing.isEmpty) return;
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'spaceId': id});
    }
  }

  bool dismissedDefaultChat(CourseDefaultChatsEnum type) {
    switch (type) {
      case CourseDefaultChatsEnum.introductions:
        return courseChatsSettings.dismissedIntroChat;
      case CourseDefaultChatsEnum.announcements:
        return courseChatsSettings.dismissedAnnouncementsChat;
    }
  }

  Future<void> dismissDefaultChatCreation(CourseDefaultChatsEnum type) async {
    final current = courseChatsSettings;
    final settings = switch (type) {
      CourseDefaultChatsEnum.introductions => current.copyWith(
        dismissedIntroChat: true,
      ),
      CourseDefaultChatsEnum.announcements => current.copyWith(
        dismissedAnnouncementsChat: true,
      ),
    };
    await setCourseChatsSettings(settings);
  }

  Future<String> addDefaultChat({
    required CourseDefaultChatsEnum type,
    required String name,
  }) async {
    final random = Random();
    final String uploadURL = switch (type) {
      CourseDefaultChatsEnum.introductions =>
        SpaceConstants.introChatIcons[random.nextInt(
          SpaceConstants.introChatIcons.length,
        )],
      CourseDefaultChatsEnum.announcements =>
        SpaceConstants.announcementChatIcons[random.nextInt(
          SpaceConstants.announcementChatIcons.length,
        )],
    };

    final resp = await client.createPangeaRoom(
      client.createRoom(
        preset: CreateRoomPreset.publicChat,
        visibility: Visibility.private,
        name: name,
        roomAliasName:
            "${type.alias}_${id.localpart}_${DateTime.now().millisecondsSinceEpoch}",
        initialState: [
          StateEvent(type: EventTypes.RoomAvatar, content: {'url': uploadURL}),
          await client.generateCustomJoinRules(
            JoinRules.knockRestricted,
            allowRoomId: id,
          ),
        ],
        powerLevelContentOverride: type.powerLevels,
      ),
    );

    try {
      await addToSpace(resp);
      if (pangeaSpaceParents.isEmpty) {
        await client
            .waitForRoomInSync(resp)
            .timeoutNamed(
              const Duration(seconds: 10),
              'waitForRoomInSync: default chats',
            );
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': resp},
        level: e is TimeoutException ? SentryLevel.warning : SentryLevel.error,
      );

      if (e is! TimeoutException) {
        rethrow;
      }
    }
    return resp;
  }
}
