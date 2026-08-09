import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat_list/course_chats_settings_model.dart';
import 'package:fluffychat/routes/chat_list/course_default_chats_enum.dart';

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
        await client.waitForRoomInSync(resp).timeout(Duration(seconds: 10));
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
