import 'dart:async';

import 'package:fluffychat/routes/invite_user/user_invite_link_repo.dart';

class UserInviteController {
  static StreamController userInviteStream = StreamController.broadcast();

  static Future<void> setInviteUser(String userId) async {
    await UserInviteLinkRepo.setInviteUser(userId);
    userInviteStream.add(userId);
  }
}
