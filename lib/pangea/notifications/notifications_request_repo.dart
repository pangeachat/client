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
  static const String _storageKey = "notif_request_info";
  static const Duration requestInterval = Duration(days: 30);

  static final GetStorage _storage = GetStorage(_boxName);

  static Future<bool> canShowRequest() async {
    final info = await _get();
    if (info == null) return true;
    final now = DateTime.now();
    final difference = now.difference(info.timestamp);
    return difference >= requestInterval;
  }

  static Future<void> updateRequestTimestamp() async {
    final info = NotifRequestInfo(DateTime.now());
    await _set(info);
  }

  static Future<NotifRequestInfo?> _get() async {
    await GetStorage.init(_boxName);
    final entry = _storage.read(_storageKey);
    if (entry == null) return null;
    try {
      return NotifRequestInfo.fromJson(Map<String, dynamic>.from(entry));
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"entry": entry});
      await _storage.remove(_storageKey);
      return null;
    }
  }

  static Future<void> _set(NotifRequestInfo info) async {
    await GetStorage.init(_boxName);
    try {
      await _storage.write(_storageKey, info.toJson());
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"notif_request_info": info.toJson()},
      );
    }
  }
}
