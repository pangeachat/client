import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/utils/platform_infos.dart';

class SessionBackup {
  final String? olmAccount;
  final String accessToken;
  final String userId;
  final String homeserver;
  final String? deviceId;
  final String? deviceName;

  const SessionBackup({
    required this.olmAccount,
    required this.accessToken,
    required this.userId,
    required this.homeserver,
    required this.deviceId,
    this.deviceName,
  });

  factory SessionBackup.fromJsonString(String json) =>
      SessionBackup.fromJson(jsonDecode(json));

  factory SessionBackup.fromJson(Map<String, dynamic> json) => SessionBackup(
    olmAccount: json['olm_account'],
    accessToken: json['access_token'],
    userId: json['user_id'],
    homeserver: json['homeserver'],
    deviceId: json['device_id'],
    deviceName: json['device_name'],
  );

  Map<String, dynamic> toJson() => {
    'olm_account': olmAccount,
    'access_token': accessToken,
    'user_id': userId,
    'homeserver': homeserver,
    'device_id': deviceId,
    if (deviceName != null) 'device_name': deviceName,
  };

  @override
  String toString() => jsonEncode(toJson());
}

extension InitWithRestoreExtension on Client {
  /// The keychain store for the session backup. Backups are written every time
  /// a client becomes logged in (see [storeSessionBackup]), including iOS
  /// background launches (push, prewarming) while the device is locked, where
  /// the plugin default accessibility
  /// (`kSecAttrAccessibleWhenUnlocked`) makes the item unreachable and the
  /// write fails with `errSecInteractionNotAllowed` (-25308, Sentry
  /// CLIENT-4ZN). `first_unlock` keeps it reachable after the first unlock
  /// since boot — the same level the database cipher uses. Both the write and
  /// the delete go through this one instance: the plugin filters deletes by
  /// accessibility, so a mismatched delete would leave the backup behind.
  static const sessionBackupStorage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static String sessionBackupKey(String clientName) =>
      '${AppSettings.applicationName.value}_session_backup_$clientName';

  static FlutterSecureStorage? get _storage =>
      PlatformInfos.isMobile || PlatformInfos.isLinux
      ? sessionBackupStorage
      : null;

  static Future<void> deleteSessionBackup(String clientName) async {
    await _storage?.delete(key: sessionBackupKey(clientName));
  }

  /// Writes this session to the backup [initWithRestore] restores from, which
  /// is also what a push handled while the app is closed authenticates with.
  ///
  /// [ClientManager.createClient] calls this every time the client becomes
  /// logged in: the end of init, a fresh login, and every access token
  /// refresh. Writing it only at startup left a token that expired within a
  /// day, because refresh tokens are in use and the server's access token
  /// lifetime is 24 hours.
  ///
  /// A write can fail before the first unlock since boot. That is a transient
  /// the next write retries, so it is reported as a warning and never thrown.
  Future<void> storeSessionBackup() async {
    final storage = _storage;
    if (storage == null) return;
    final accessToken = this.accessToken;
    final homeserver = this.homeserver?.toString();
    final deviceId = deviceID;
    final userId = userID;
    if (accessToken == null ||
        homeserver == null ||
        deviceId == null ||
        userId == null) {
      return;
    }
    Logs().v('Store session in backup');
    try {
      await storage.write(
        key: sessionBackupKey(clientName),
        value: SessionBackup(
          olmAccount: encryption?.pickledOlmAccount,
          accessToken: accessToken,
          deviceId: deviceId,
          homeserver: homeserver,
          deviceName: deviceName,
          userId: userId,
        ).toString(),
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'client_name': clientName},
        level: SentryLevel.warning,
      );
    }
  }

  Future<void> initWithRestore({void Function()? onMigration}) async {
    final storageKey = sessionBackupKey(clientName);
    final storage = _storage;

    try {
      await init(
        onInitStateChanged: (state) {
          if (state == InitState.migratingDatabase) onMigration?.call();
        },
        waitForFirstSync: false,
        waitUntilLoadCompletedLoaded: false,
      );
    } catch (e, s) {
      Logs().wtf('Client init failed!', e, s);
      final sessionBackupString = await storage?.read(key: storageKey);
      if (sessionBackupString == null) {
        rethrow;
      }

      try {
        final sessionBackup = SessionBackup.fromJsonString(sessionBackupString);
        await init(
          newToken: sessionBackup.accessToken,
          newOlmAccount: sessionBackup.olmAccount,
          newDeviceID: sessionBackup.deviceId,
          newDeviceName: sessionBackup.deviceName,
          newHomeserver: Uri.tryParse(sessionBackup.homeserver),
          newUserID: sessionBackup.userId,
          waitForFirstSync: false,
          waitUntilLoadCompletedLoaded: false,
          onInitStateChanged: (state) {
            if (state == InitState.migratingDatabase) onMigration?.call();
          },
        );
      } catch (e, s) {
        Logs().wtf('Restore client failed!', e, s);
        rethrow;
      }
    }
  }
}
