import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/builder.dart';

/// The builder deletes the database file on a failed open and then retries
/// once, because that cleanup is what used to make the *next* app launch
/// succeed while the current one died (CLIENT-9FB, #8658).
///
/// What matters is the count: exactly two attempts. One means the retry was
/// dropped; three or more means it recursed, which would turn a persistent
/// failure into a loop instead of a launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    final tempDir = await Directory.systemTemp.createTemp('builder_retry');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
  });

  Future<MatrixSdkDatabase> workingDatabase() async => MatrixSdkDatabase.init(
    'builder_retry_test',
    database: await databaseFactoryFfi.openDatabase(':memory:'),
    sqfliteFactory: databaseFactoryFfi,
  );

  test(
    'retries once and returns the database when the first open fails',
    () async {
      var attempts = 0;

      final database = await flutterMatrixSdkDatabaseBuilder(
        'builder_retry_test',
        constructDatabase: (_) async {
          attempts++;
          if (attempts == 1) throw Exception('first open fails');
          return workingDatabase();
        },
      );

      expect(
        attempts,
        2,
        reason: 'the failed open should be retried exactly once',
      );
      expect(database, isNotNull);
    },
  );

  test('gives up after the retry rather than recursing', () async {
    var attempts = 0;

    await expectLater(
      flutterMatrixSdkDatabaseBuilder(
        'builder_retry_test',
        constructDatabase: (_) async {
          attempts++;
          throw Exception('open fails every time');
        },
      ),
      throwsA(isA<Exception>()),
    );

    expect(
      attempts,
      2,
      reason: 'a persistent failure must stop after one retry',
    );
  });

  test('does not retry when the first open succeeds', () async {
    var attempts = 0;

    await flutterMatrixSdkDatabaseBuilder(
      'builder_retry_test',
      constructDatabase: (_) async {
        attempts++;
        return workingDatabase();
      },
    );

    expect(attempts, 1);
  });
}
