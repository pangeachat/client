import 'package:get_storage/get_storage.dart';

class _StyleSettings {
  final double fontSizeFactor;

  const _StyleSettings({
    this.fontSizeFactor = 1.0,
  });

  Map<String, dynamic> toJson() {
    return {
      'fontSizeFactor': fontSizeFactor,
    };
  }

  factory _StyleSettings.fromJson(Map<String, dynamic> json) {
    return _StyleSettings(
      fontSizeFactor: (json['fontSizeFactor'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class StyleSettingsRepo {
  static final GetStorage _storage = GetStorage("style_settings");

  static Future<double> fontSizeFactor(String userId) async {
    await GetStorage.init("style_settings");
    final json =
        _storage.read<Map<String, dynamic>>('${userId}_style_settings');
    final settings =
        json != null ? _StyleSettings.fromJson(json) : const _StyleSettings();
    return settings.fontSizeFactor;
  }

  static Future<void> setFontSizeFactor(String userId, double factor) async {
    await GetStorage.init("style_settings");
    final settings = _StyleSettings(fontSizeFactor: factor);
    await _storage.write('${userId}_style_settings', settings.toJson());
  }
}
