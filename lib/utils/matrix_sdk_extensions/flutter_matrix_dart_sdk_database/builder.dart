import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'cipher.dart';

import 'sqlcipher_stub.dart'
    if (dart.library.io) 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

Future<DatabaseApi> flutterMatrixSdkDatabaseBuilder(String clientName) async {
  MatrixSdkDatabase? database;
  try {
    database = await _constructDatabase(clientName);
    await database.open();
    return database;
  } catch (e, s) {
    // #Pangea
    ErrorHandler.logError(
      e: e,
      s: s,
      data: {"clientID": clientName},
      m: "Failed to open matrix sdk database. Openning fallback database.",
    );
    // Pangea#
    Logs().wtf('Unable to construct database!', e, s);

    try {
      // #Pangea
      // // Send error notification:
      // final l10n = await lookupL10n(PlatformDispatcher.instance.locale);
      // ClientManager.sendInitNotification(
      //   l10n.initAppError,
      //   e.toString(),
      // );
      // Pangea#
    } catch (e, s) {
      Logs().e('Unable to send error notification', e, s);
    }

    // Try to delete database so that it can created again on next init:
    database?.delete().catchError(
        // #Pangea
        (err, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {},
        m: "Failed to delete matrix database after failed construction.",
      );
    }
        // (e, s) => Logs().wtf(
        //   'Unable to delete database, after failed construction',
        //   e,
        //   s,
        // ),
        // Pangea#
        );

    // Delete database file:
    if (!kIsWeb) {
      final dbFile = File(await _getDatabasePath(clientName));
      if (await dbFile.exists()) await dbFile.delete();
    }

    rethrow;
  }
}

Future<MatrixSdkDatabase> _constructDatabase(String clientName) async {
  if (kIsWeb) {
    html.window.navigator.storage?.persist();
    return await MatrixSdkDatabase.init(clientName);
  }

  final cipher = await getDatabaseCipher();
  // #Pangea
  Sentry.addBreadcrumb(Breadcrumb(message: 'Database cipher: $cipher'));
  // Pangea#

  Directory? fileStorageLocation;
  try {
    final tmpDir = await getTemporaryDirectory();
    final appTmpDir = Directory(join(tmpDir.path, clientName));
    if (!await appTmpDir.exists()) {
      await appTmpDir.create(recursive: true);
    }
    fileStorageLocation = appTmpDir;
  } on MissingPlatformDirectoryException catch (_) {
    Logs().w(
      'No temporary directory for file cache available on this platform.',
    );
  }

  final path = await _getDatabasePath(clientName);

  // fix dlopen for old Android
  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
  // import the SQLite / SQLCipher shared objects / dynamic libraries
  final factory =
      createDatabaseFactoryFfi(ffiInit: SQfLiteEncryptionHelper.ffiInit);

  // #Pangea
  Sentry.addBreadcrumb(Breadcrumb(message: 'Database path: $path'));
  // Pangea#

  // required for [getDatabasesPath]
  databaseFactory = factory;

  // migrate from potential previous SQLite database path to current one
  await _migrateLegacyLocation(path, clientName);

  // in case we got a cipher, we use the encryption helper
  // to manage SQLite encryption
  final helper = cipher == null
      ? null
      : SQfLiteEncryptionHelper(
          factory: factory,
          path: path,
          cipher: cipher,
        );
  // #Pangea
  Sentry.addBreadcrumb(Breadcrumb(message: 'Database cipher helper: $helper'));
  // Pangea#

  // check whether the DB is already encrypted and otherwise do so
  await helper?.ensureDatabaseFileEncrypted();

  final database = await factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      // most important : apply encryption when opening the DB
      onConfigure: helper?.applyPragmaKey,
    ),
  );

  return await MatrixSdkDatabase.init(
    clientName,
    database: database,
    maxFileSize: 1000 * 1000 * 10,
    fileStorageLocation: fileStorageLocation?.uri,
    deleteFilesAfterDuration: const Duration(days: 30),
  );
}

Future<String> _getDatabasePath(String clientName) async {
  final databaseDirectory = PlatformInfos.isIOS || PlatformInfos.isMacOS
      ? await getLibraryDirectory()
      : await getApplicationSupportDirectory();

  return join(databaseDirectory.path, '$clientName.sqlite');
}

Future<void> _migrateLegacyLocation(
  String sqlFilePath,
  String clientName,
) async {
  final oldPath = PlatformInfos.isDesktop
      ? (await getApplicationSupportDirectory()).path
      : await getDatabasesPath();

  final oldFilePath = join(oldPath, clientName);
  if (oldFilePath == sqlFilePath) return;

  final maybeOldFile = File(oldFilePath);
  if (await maybeOldFile.exists()) {
    Logs().i(
      'Migrate legacy location for database from "$oldFilePath" to "$sqlFilePath"',
    );
    await maybeOldFile.copy(sqlFilePath);
    await maybeOldFile.delete();
  }
}
