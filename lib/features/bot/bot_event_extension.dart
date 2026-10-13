import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/bot_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

extension BotEventExtension on Event {
  /// A notice's optional app path (deep-linking.instructions.md).
  static const noticeDestinationPathKey = 'pangea.destination.path';
  static const noticeCheckInTypeKey = 'check_in_type';

  /// pangea-bot posts this notice's topic as its own message once the notice
  /// is read, so the notice itself stays hidden (notices.instructions.md).
  static const _realizedNoticeType = 'suggest_topic';

  bool get isFirstBotDMMessage =>
      content[PangeaEventTypes.firstBotDMMessage] == true;

  bool get isBotNotice => type == PangeaEventTypes.botNotice;

  /// Whether the bot DM shows this notice as the bot's message.
  bool get isShownBotNotice =>
      isBotNotice &&
      senderId == BotName.byEnvironment &&
      room.isBotDM &&
      content.tryGet<String>(noticeCheckInTypeKey) != _realizedNoticeType &&
      noticeBody != null;

  String? get noticeBody {
    final body = content.tryGet<String>('body');
    return body == null || body.isEmpty ? null : body;
  }

  /// Whether the notice names a place to open: a session or an app path.
  bool get hasNoticeDestination =>
      (coursePingSessionRoomId?.isNotEmpty == true &&
          coursePingActivityId?.isNotEmpty == true) ||
      PRoutes.isAppPath(content.tryGet<String>(noticeDestinationPathKey) ?? '');
}
