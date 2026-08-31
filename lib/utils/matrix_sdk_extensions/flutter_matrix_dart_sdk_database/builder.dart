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

/// Opens the Matrix SDK database, retrying once if the first attempt fails.
///
/// [constructDatabase] exists only so a test can fail the first attempt; it
/// defaults to the real [_constructDatabase].
Future<DatabaseApi> flutterMatrixSdkDatabaseBuilder(
  String clientName, {
  @visibleForTesting
  Future<MatrixSdkDatabase> Function(String clientName)? constructDatabase,
}) async {
  final construct = constructDatabase ?? _constructDatabase;
  MatrixSdkDatabase? database;
  try {
    database = await construct(clientName);
    await database.open();
    return database;
  } catch (e, s) {
    ErrorHandler.logError(
      e: e,
      s: s,
      data: {"clientID": clientName},
      m: "Failed to open matrix sdk database. Retrying once on a clean file.",
    );
    Logs().wtf('Unable to construct database!', e, s);

    try {
      // Send error notification:
      // Disabled for Pangea:
      // final l10n = await lookupL10n(PlatformDispatcher.instance.locale);
      // ClientManager.sendInitNotification(l10n.initAppError, e.toString());
    } catch (e, s) {
      Logs().e('Unable to send error notification', e, s);
    }

    // Try to delete database so that it can created again on next init:
    // Awaited, unlike upstream's fire-and-forget: the retry below reopens this
    // same path, so an unawaited delete races it. The handler also reports its
    // own error rather than re-reporting the open failure.
    try {
      await database?.delete();
    } catch (deleteError, deleteStack) {
      ErrorHandler.logError(
        e: deleteError,
        s: deleteStack,
        data: {"clientID": clientName},
        m: "Failed to delete matrix database after failed construction.",
      );
    }

    // Delete database file:
    if (!kIsWeb) {
      final dbFile = File(await _getDatabasePath(clientName));
      if (await dbFile.exists()) await dbFile.delete();
    }

    // The cleanup above is exactly what let the *next* launch succeed while
    // this one died, so spend the retry here rather than a whole app launch
    // (CLIENT-9FB, #8658). One extra attempt, not recursive, so a persistent
    // failure still terminates.
    try {
      database = await construct(clientName);
      await database.open();
      return database;
    } catch (retryError, retryStack) {
      ErrorHandler.logError(
        e: retryError,
        s: retryStack,
        data: {"clientID": clientName},
        m: "Matrix sdk database retry failed after cleanup.",
      );
      rethrow;
    }
  }
}

Future<MatrixSdkDatabase> _constructDatabase(String clientName) async {
  if (kIsWeb) {
    html.window.navigator.storage?.persist();
    return await MatrixSdkDatabase.init(clientName);
  }

  final cipher = await getDatabaseCipher();
  Sentry.addBreadcrumb(Breadcrumb(message: 'Database cipher: $cipher'));

  Directory? fileStorageLocation;
  try {
    fileStorageLocation = await getTemporaryDirectory();
  } on MissingPlatformDirectoryException catch (_) {
    Logs().w(
      'No temporary directory for file cache available on this platform.',
    );
  }

  final path = await _getDatabasePath(clientName);

  // fix dlopen for old Android
  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
  // import the SQLite / SQLCipher shared objects / dynamic libraries
  final factory = createDatabaseFactoryFfi(
    ffiInit: SQfLiteEncryptionHelper.ffiInit,
  );

  Sentry.addBreadcrumb(Breadcrumb(message: 'Database path: $path'));

  // required for [getDatabasesPath]
  databaseFactory = factory;

  // migrate from potential previous SQLite database path to current one
  await _migrateLegacyLocation(path, clientName);

  // in case we got a cipher, we use the encryption helper
  // to manage SQLite encryption
  final helper = cipher == null
      ? null
      : SQfLiteEncryptionHelper(factory: factory, path: path, cipher: cipher);
  Sentry.addBreadcrumb(Breadcrumb(message: 'Database cipher helper: $helper'));

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
