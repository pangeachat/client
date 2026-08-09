import 'package:get_storage/get_storage.dart';

class LanguageMismatchRepo {
  static final GetStorage _storage = GetStorage('language_mismatch');
  static const Duration displayInterval = Duration(minutes: 30);

  static String _roomKey(String roomId) => 'language_mismatch_room_$roomId';

  static bool shouldShowByRoom(String roomId) => _get(_roomKey(roomId));

  static Future<void> setRoom(String roomId) async => _set(_roomKey(roomId));

  static Future<void> _set(String key) async {
    await _storage.write(key, DateTime.now().toIso8601String());
  }

  static bool _get(String key) {
    final lastShown = _getCached(key);
    if (lastShown == null) return true;
    return DateTime.now().difference(lastShown) >= displayInterval;
  }

  static DateTime? _getCached(String key) {
    final entry = _storage.read(key);
    if (entry == null) return null;

    final value = DateTime.tryParse(entry);
    if (value == null) {
      _storage.remove(key);
      return null;
    }

    final timeSince = DateTime.now().difference(value);
    if (timeSince > displayInterval) {
      _storage.remove(key);
      return null;
    }
    return value;
  }
}
