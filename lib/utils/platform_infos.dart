import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/config/setting_keys.dart';

abstract class PlatformInfos {
  static bool get isWeb => kIsWeb;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  // #Pangea
  // static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isWindows => getOperatingSystem() == 'Windows';
  // Pangea#
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static bool get isCupertinoStyle => isIOS || isMacOS;

  static bool get isMobile => isAndroid || isIOS;

  /// For desktops which don't support ChachedNetworkImage yet
  static bool get isBetaDesktop => isWindows || isLinux;

  static bool get isDesktop => isLinux || isWindows || isMacOS;

  static bool get usesTouchscreen => !isMobile;

  static bool get supportsVideoPlayer =>
      // #Pangea
      // !PlatformInfos.isWindows && !PlatformInfos.isLinux;
      !PlatformInfos.isLinux;
  // Pangea#

  /// Web could also record in theory but currently only wav which is too large
  /// #Pangea
  // static bool get platformCanRecord => (isMobile || isMacOS);
  static bool get platformCanRecord => (isMobile || isMacOS || isWeb);
  // Pangea#

  static String get clientName =>
      '${AppSettings.applicationName.value} ${isWeb ? 'web' : Platform.operatingSystem}${kReleaseMode ? '' : 'Debug'}';

  static Future<String> getVersion() async {
    var version = kIsWeb ? 'Web' : 'Unknown';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    return version;
  }

  // #Pangea
  static String? getOperatingSystem() {
    if (!kIsWeb) return null;
    final String platform = html.window.navigator.platform?.toLowerCase() ?? '';

    if (platform.contains('mac')) {
      return 'macOS';
    } else if (platform.contains('win')) {
      return 'Windows';
    } else if (platform.contains('linux')) {
      return 'Linux';
    }
    return null;
  }

  // Pangea#
}
