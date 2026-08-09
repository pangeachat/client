import 'package:get_storage/get_storage.dart';

class UserInviteLinkRepo {
  static final GetStorage _storage = GetStorage('user_invite_storage');
  static final String _inviteUserKey = 'invite_user';

  static String? get inviteUser => _storage.read(_inviteUserKey);

  static Future<void> setInviteUser(String value) =>
      _storage.write(_inviteUserKey, value);

  static Future<void> clearInviteUser() => _storage.remove(_inviteUserKey);
}
