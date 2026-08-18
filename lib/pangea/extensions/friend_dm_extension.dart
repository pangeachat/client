import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/bot_room_extension.dart';
import 'package:fluffychat/features/support/support_client_extension.dart';

/// A "friend DM" is a direct chat with another person — anyone other than
/// Pangea Bot or the support account. The chat list's invite-a-friend prompt
/// (#8395) shows until the learner has one.
extension FriendDMRoomExtension on Room {
  bool get isFriendDM => isDirectChat && !isBotDM && !isSupportDM;
}

extension FriendDMClientExtension on Client {
  bool get hasFriendDM => rooms.any((room) => room.isFriendDM);
}
