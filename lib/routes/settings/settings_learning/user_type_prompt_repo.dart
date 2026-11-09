import 'package:fluffychat/pangea/common/utils/expiring_storage_box.dart';

/// When this device last asked an account with no self-identified role for
/// one, so it asks at most once a day.
class UserTypePromptRepo {
  static const Duration askInterval = Duration(days: 1);

  static final ExpiringStorageBox _asked = ExpiringStorageBox(
    'user_type_prompt',
    ttl: askInterval,
    payloadKey: 'asked',
  );

  static Future<bool> canAsk(String userId) async =>
      await _asked.read(userId) == null;

  static Future<void> markAsked(String userId) =>
      _asked.write(userId, const <String, dynamic>{});
}
