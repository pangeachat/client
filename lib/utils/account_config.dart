import 'package:matrix/matrix.dart';

extension ApplicationAccountConfigExtension on Client {
  static const String accountDataKey = 'im.fluffychat.account_config';

  ApplicationAccountConfig get applicationAccountConfig =>
      ApplicationAccountConfig.fromJson(
        accountData[accountDataKey]?.content ?? {},
      );

  /// The config after each sync that changed it, so a screen already showing
  /// the wallpaper can follow a change made in settings.
  Stream<ApplicationAccountConfig> get applicationAccountConfigUpdates => onSync
      .stream
      .where(
        (syncUpdate) =>
            syncUpdate.accountData?.any(
              (accountData) => accountData.type == accountDataKey,
            ) ??
            false,
      )
      .map((_) => applicationAccountConfig);

  Future<void> setApplicationAccountConfig(ApplicationAccountConfig config) =>
      setAccountData(userID!, accountDataKey, config.toJson());

  /// Only updates the specified values in ApplicationAccountConfig
  Future<void> updateApplicationAccountConfig(ApplicationAccountConfig config) {
    final currentConfig = applicationAccountConfig;
    return setAccountData(
      userID!,
      accountDataKey,
      ApplicationAccountConfig(
        wallpaperUrl: config.wallpaperUrl ?? currentConfig.wallpaperUrl,
        wallpaperOpacity:
            config.wallpaperOpacity ?? currentConfig.wallpaperOpacity,
        wallpaperBlur: config.wallpaperBlur ?? currentConfig.wallpaperBlur,
      ).toJson(),
    );
  }
}

class ApplicationAccountConfig {
  final Uri? wallpaperUrl;
  final double? wallpaperOpacity;
  final double? wallpaperBlur;

  const ApplicationAccountConfig({
    this.wallpaperUrl,
    this.wallpaperOpacity,
    this.wallpaperBlur,
  });

  static double _sanitizedOpacity(double? opacity) {
    if (opacity == null) return 1;
    if (opacity > 1 || opacity < 0) return 1;
    return opacity;
  }

  factory ApplicationAccountConfig.fromJson(Map<String, dynamic> json) =>
      ApplicationAccountConfig(
        wallpaperUrl: json['wallpaper_url'] is String
            ? Uri.tryParse(json['wallpaper_url'])
            : null,
        wallpaperOpacity: _sanitizedOpacity(
          json.tryGet<double>('wallpaper_opacity'),
        ),
        wallpaperBlur: json.tryGet<double>('wallpaper_blur'),
      );

  Map<String, dynamic> toJson() => {
    'wallpaper_url': wallpaperUrl?.toString(),
    'wallpaper_opacity': wallpaperOpacity,
    'wallpaper_blur': wallpaperBlur,
  };
}
