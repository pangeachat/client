import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/builder.dart';

/// sqflite quotes the failing statement in its exceptions, and the statements
/// that open the encrypted database carry its key. The builder reports and
/// rethrows those failures, so the key has to be gone before either happens
/// (CLIENT-9FB, #9346).
void main() {
  const cipher = 'N0tARealKey_0123456789abcdefghijklmnopqrstu=';

  setUpAll(sqfliteFfiInit);

  // A real sqflite failure on a statement shaped like the SDK's
  // `PRAGMA KEY='<cipher>';`. Plain SQLite ignores an unknown pragma, so the
  // trailing token is what makes this one fail.
  Future<void> failingKeyStatement() async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    try {
      await database.rawQuery("PRAGMA KEY='$cipher' oops;");
    } finally {
      await database.close();
    }
  }

  test('sqflite puts the failing statement, key included, in its error', () {
    // The premise of the redaction. If sqflite stops quoting statements this
    // fails, and the tests below no longer prove anything.
    expect(
      failingKeyStatement,
      throwsA(
        isA<Object>().having((e) => e.toString(), 'text', contains(cipher)),
      ),
    );
  });

  test('a failure carrying the key is rethrown without it', () {
    expect(
      redactingCipher(cipher, failingKeyStatement),
      throwsA(
        isA<RedactedDatabaseException>().having(
          (e) => e.toString(),
          'text',
          allOf(
            isNot(contains(cipher)),
            contains("PRAGMA KEY='[redacted]'"),
            // The diagnosis survives: only the key is removed.
            contains('syntax error'),
          ),
        ),
      ),
    );
  });

  test('a failure without the key is rethrown as it was', () {
    final error = StateError('SQLCipher library is not available');

    expect(
      redactingCipher(cipher, () async => throw error),
      throwsA(same(error)),
    );
    // No key (encryption unsupported on this platform): nothing to redact.
    expect(
      redactingCipher(null, () async => throw error),
      throwsA(same(error)),
    );
  });
}
