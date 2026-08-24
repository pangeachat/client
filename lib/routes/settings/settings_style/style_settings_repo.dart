import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// A stored blob written before issue #7719 still carries a `fontSizeFactor`
/// key. Nothing reads it, and [StyleSettings.fromJson] ignores unknown keys, so
/// it simply drops out the next time the blob is written.
class StyleSettings {
  final bool useActivityImageBackground;

  const StyleSettings({this.useActivityImageBackground = true});

  Map<String, dynamic> toJson() {
    return {'useActivityImageBackground': useActivityImageBackground};
  }

  factory StyleSettings.fromJson(Map<String, dynamic> json) {
    return StyleSettings(
      useActivityImageBackground:
          json['useActivityImageBackground'] as bool? ?? true,
    );
  }

  StyleSettings copyWith({bool? useActivityImageBackground}) {
    return StyleSettings(
      useActivityImageBackground:
          useActivityImageBackground ?? this.useActivityImageBackground,
    );
  }
}

class StyleSettingsRepo {
  static final GetStorage _storage = GetStorage("style_settings");

  static String _storageKey(String userId) => '${userId}_style_settings';

  static Future<StyleSettings> settings(String userId) async {
    await GetStorage.init("style_settings");
    final key = _storageKey(userId);
    final json = _storage.read<Map<String, dynamic>>(key);
    if (json == null) return const StyleSettings();
    try {
      return StyleSettings.fromJson(json);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"settings_entry": json});
      _storage.remove(key);
      return const StyleSettings();
    }
  }

  static Future<void> setUseActivityImageBackground(
    String userId,
    bool useBackground,
  ) async {
    final currentSettings = await settings(userId);
    final updatedSettings = currentSettings.copyWith(
      useActivityImageBackground: useBackground,
    );
    await _storage.write(_storageKey(userId), updatedSettings.toJson());
  }
}
