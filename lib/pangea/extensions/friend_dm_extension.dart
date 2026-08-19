import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/bot_room_extension.dart';
import 'package:fluffychat/features/support/support_client_extension.dart';

/// A "friend DM" is a direct chat with another person — anybody other than
/// Pangea Bot, the support account, or the learner themselves. The chat list's
/// invite-a-friend prompt (#8395) shows until the learner has one, so the DMs
/// the app offers unasked must not count as having reached out to somebody.
extension FriendDMRoomExtension on Room {
  bool get isFriendDM =>
      isDirectChat &&
      !isBotDM &&
      !isSupportDM &&
      directChatMatrixID != client.userID;
}

extension FriendDMClientExtension on Client {
  bool get hasFriendDM => rooms.any((room) => room.isFriendDM);
}
