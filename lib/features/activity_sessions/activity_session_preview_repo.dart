import 'package:get_storage/get_storage.dart';

class ActivitySessionPreviewRepo {
  static const String _storageKey = 'activity_session_preview_storage';
  static final GetStorage _storage = GetStorage(_storageKey);

  static Future<List<String>> getPreviewedRoomIds() async {
    await GetStorage.init(_storageKey);
    final keys = _storage.getKeys();
    return keys.whereType<String>().toList();
  }

  static Future<bool> hasPreviewedRoom(String roomId) async {
    await GetStorage.init(_storageKey);
    return _storage.hasData(roomId);
  }

  static Future<void> set(String roomId) async {
    await GetStorage.init(_storageKey);
    await _storage.write(roomId, DateTime.now().microsecondsSinceEpoch);
  }

  static Future<void> remove(String roomId) async {
    await GetStorage.init(_storageKey);
    await _storage.remove(roomId);
  }
}
