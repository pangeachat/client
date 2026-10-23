import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/setting_keys.dart';

const _passwordStorageKey = 'database_password';

Future<String?> getDatabaseCipher() async {
  String? password;

  try {
    // #Pangea
    // mogol/flutter_secure_storage#532
    // mogol/flutter_secure_storage#524
    // Pangea#
    const secureStorage = FlutterSecureStorage(
      // #Pangea
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      // Pangea#
    );
    // #Pangea
    await secureStorage.read(key: _passwordStorageKey);
    // Pangea#
    final containsEncryptionKey =
        await secureStorage.read(key: _passwordStorageKey) != null;
    if (!containsEncryptionKey) {
      final rng = Random.secure();
      final list = Uint8List(32);
      list.setAll(0, Iterable.generate(list.length, (i) => rng.nextInt(256)));
      final newPassword = base64UrlEncode(list);
      await secureStorage.write(key: _passwordStorageKey, value: newPassword);
    }
    // workaround for if we just wrote to the key and it still doesn't exist
    password = await secureStorage.read(key: _passwordStorageKey);
    if (password == null) {
      throw MissingPluginException(
        // #Pangea
        "password is null after storing new password",
        // Pangea#
      );
    }
  } on MissingPluginException catch (e) {
    const FlutterSecureStorage()
        .delete(key: _passwordStorageKey)
        .catchError((_) {});
    Logs().w('Database encryption is not supported on this platform', e);
    _sendNoEncryptionWarning(e);
  } catch (e, s) {
    const FlutterSecureStorage()
        .delete(key: _passwordStorageKey)
        .catchError((_) {});
    Logs().w('Unable to init database encryption', e, s);
    _sendNoEncryptionWarning(e);
  }

  return password;
}

void _sendNoEncryptionWarning(Object exception) async {
  final isStored = AppSettings.noEncryptionWarningShown.value;

  if (isStored == true) return;

  // #Pangea
  // final l10n = await lookupL10n(PlatformDispatcher.instance.locale);
  // ClientManager.sendInitNotification(
  //   l10n.noDatabaseEncryption,
  //   exception.toString(),
  // );
  // Pangea#

  await AppSettings.noEncryptionWarningShown.setItem(true);
}
