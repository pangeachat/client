import 'dart:async';
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
  /// The keychain store for the session backup. Backups are written on every
  /// client init, including iOS background launches (push, prewarming) while
  /// the device is locked, where the plugin default accessibility
  /// (`kSecAttrAccessibleWhenUnlocked`) makes the item unreachable and the
  /// write fails with `errSecInteractionNotAllowed` (-25308, Sentry
  /// CLIENT-4ZN). `first_unlock` keeps it reachable after the first unlock
  /// since boot — the same level the database cipher uses. Both the write and
  /// the delete go through this one instance: the plugin filters deletes by
  /// accessibility, so a mismatched delete would leave the backup behind.
  static const sessionBackupStorage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<void> deleteSessionBackup(String clientName) async {
    final storage = PlatformInfos.isMobile || PlatformInfos.isLinux
        ? sessionBackupStorage
        : null;
    await storage?.delete(
      key: '${AppSettings.applicationName.value}_session_backup_$clientName',
    );
  }

  Future<void> initWithRestore({void Function()? onMigration}) async {
    final storageKey =
        '${AppSettings.applicationName.value}_session_backup_$clientName';
    final storage = PlatformInfos.isMobile || PlatformInfos.isLinux
        ? sessionBackupStorage
        : null;

    try {
      await init(
        onInitStateChanged: (state) {
          if (state == InitState.migratingDatabase) onMigration?.call();
        },
        waitForFirstSync: false,
        waitUntilLoadCompletedLoaded: false,
      );
      if (isLogged()) {
        final accessToken = this.accessToken;
        final homeserver = this.homeserver?.toString();
        final deviceId = deviceID;
        final userId = userID;
        final hasBackup =
            accessToken != null &&
            homeserver != null &&
            deviceId != null &&
            userId != null;
        assert(hasBackup);
        if (hasBackup) {
          Logs().v('Store session in backup');
          // Deliberately not awaited (init latency), but no longer left to
          // fail as an unhandled async error either: a backup write can still
          // fail before the first unlock since boot, and that is a transient
          // the next launch retries — a warning, not an error. Handled here
          // rather than awaited inside this try so a write failure can never
          // trip the restore path below.
          unawaited(
            storage
                ?.write(
                  key: storageKey,
                  value: SessionBackup(
                    olmAccount: encryption?.pickledOlmAccount,
                    accessToken: accessToken,
                    deviceId: deviceId,
                    homeserver: homeserver,
                    deviceName: deviceName,
                    userId: userId,
                  ).toString(),
                )
                .catchError(
                  (Object e, StackTrace s) => ErrorHandler.logError(
                    e: e,
                    s: s,
                    m: 'Failed to store session backup',
                    data: {'client_name': clientName},
                    level: SentryLevel.warning,
                  ),
                ),
          );
        }
      }
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
