import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

class NotifRequestInfo {
  final DateTime timestamp;

  NotifRequestInfo(this.timestamp);

  Map<String, dynamic> toJson() => {"timestamp": timestamp.toIso8601String()};

  factory NotifRequestInfo.fromJson(Map<String, dynamic> json) {
    return NotifRequestInfo(DateTime.parse(json["timestamp"] as String));
  }
}

class NotificationsRequestRepo {
  static const String _boxName = "notifications_request_storage";
  static const Duration requestInterval = Duration(days: 30);

  static final GetStorage _storage = GetStorage(_boxName);

  static String _storageKey(String userId) => "notif_request_info_$userId";

  static Future<bool> canShowRequest(String userId) async {
    final info = await _get(userId);
    if (info == null) return true;
    final now = DateTime.now();
    final difference = now.difference(info.timestamp);
    return difference >= requestInterval;
  }

  static Future<void> updateRequestTimestamp(String userId) async {
    final info = NotifRequestInfo(DateTime.now());
    await _set(info, userId);
  }

  static Future<NotifRequestInfo?> _get(String userId) async {
    await GetStorage.init(_boxName);
    final entry = _storage.read(_storageKey(userId));
    if (entry == null) return null;
    try {
      return NotifRequestInfo.fromJson(Map<String, dynamic>.from(entry));
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"entry": entry});
      await _storage.remove(_storageKey(userId));
      return null;
    }
  }

  static Future<void> _set(NotifRequestInfo info, String userId) async {
    await GetStorage.init(_boxName);
    try {
      await _storage.write(_storageKey(userId), info.toJson());
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"notif_request_info": info.toJson()},
      );
    }
  }
}
