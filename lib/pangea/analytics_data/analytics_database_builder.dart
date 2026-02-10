import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/pangea/analytics_data/analytics_database.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/sqlcipher_stub.dart';
import 'package:fluffychat/utils/platform_infos.dart';

Future<AnalyticsDatabase> analyticsDatabaseBuilder(String name) async {
  AnalyticsDatabase? database;
  try {
    database = await _constructDatabase(name);
    await database.open();
    return database;
  } catch (e, s) {
    ErrorHandler.logError(
      e: e,
      s: s,
      data: {"clientID": name},
      m: "Failed to open analytics database. Opening fallback database.",
    );

    Logs().wtf('Unable to construct database!', e, s);
    // Try to delete database so that it can created again on next init:
    database?.delete().catchError((err, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {},
        m: "Failed to delete analytics database after failed construction.",
      );
    });

    // Delete database file:
    if (database == null && !kIsWeb) {
      final dbFile = File(await _getDatabasePath(name));
      if (await dbFile.exists()) await dbFile.delete();
    }

    rethrow;
  }
}

Future<AnalyticsDatabase> _constructDatabase(String name) async {
  if (kIsWeb) {
    html.window.navigator.storage?.persist();
    return await AnalyticsDatabase.init(name);
  }

  Directory? fileStorageLocation;
  try {
    fileStorageLocation = await getTemporaryDirectory();
  } on MissingPlatformDirectoryException catch (_) {
    Logs().w(
      'No temporary directory for file cache available on this platform.',
    );
  }

  final path = await _getDatabasePath(name);

  // fix dlopen for old Android
  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
  // import the SQLite / SQLCipher shared objects / dynamic libraries
  final factory = createDatabaseFactoryFfi(
    ffiInit: SQfLiteEncryptionHelper.ffiInit,
  );

  // required for [getDatabasesPath]
  databaseFactory = factory;
  final database = await factory.openDatabase(
    path,
    options: OpenDatabaseOptions(version: 1),
  );

  return await AnalyticsDatabase.init(
    name,
    database: database,
    fileStorageLocation: fileStorageLocation?.uri,
    deleteFilesAfterDuration: const Duration(days: 30),
  );
}

Future<String> _getDatabasePath(String name) async {
  final databaseDirectory = PlatformInfos.isIOS || PlatformInfos.isMacOS
      ? await getLibraryDirectory()
      : await getApplicationSupportDirectory();

  return join(databaseDirectory.path, '$name.sqlite');
}
