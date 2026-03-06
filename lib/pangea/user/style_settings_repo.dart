import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

class StyleSettings {
  final double fontSizeFactor;
  final bool useActivityImageBackground;

  const StyleSettings({
    this.fontSizeFactor = 1.0,
    this.useActivityImageBackground = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'fontSizeFactor': fontSizeFactor,
      'useActivityImageBackground': useActivityImageBackground,
    };
  }

  factory StyleSettings.fromJson(Map<String, dynamic> json) {
    return StyleSettings(
      fontSizeFactor: (json['fontSizeFactor'] as num?)?.toDouble() ?? 1.0,
      useActivityImageBackground:
          json['useActivityImageBackground'] as bool? ?? true,
    );
  }

  StyleSettings copyWith({
    double? fontSizeFactor,
    bool? useActivityImageBackground,
  }) {
    return StyleSettings(
      fontSizeFactor: fontSizeFactor ?? this.fontSizeFactor,
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

  static Future<void> setFontSizeFactor(String userId, double factor) async {
    final currentSettings = await settings(userId);
    final updatedSettings = currentSettings.copyWith(fontSizeFactor: factor);
    await _storage.write(_storageKey(userId), updatedSettings.toJson());
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
