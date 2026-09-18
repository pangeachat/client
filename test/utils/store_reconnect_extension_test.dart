// IndexedDB only exists in a browser, so the VM suite skips this file. Run it
// with `fvm flutter test --platform chrome test/utils/store_reconnect_extension_test.dart`.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/matrix_sdk_extensions/store_reconnect_extension.dart';

const _name = 'store_reconnect_extension_test';
const _userId = '@learner:example.org';

Future<int> _insertClient(MatrixSdkDatabase database) => database.insertClient(
  _name,
  'https://example.org',
  'token',
  null,
  null,
  _userId,
  null,
  null,
  null,
  null,
);

void main() {
  test('a login survives a store connection the browser dropped', () async {
    final database = await MatrixSdkDatabase.init(_name);
    final client = Client(_name, database: database);

    // The state iOS Safari leaves behind: a handle that is closing for good.
    await database.close();
    await expectLater(
      _insertClient(database),
      throwsA(predicate((e) => e.toString().contains('connection is closing'))),
    );

    await client.reconnectStore();

    await _insertClient(database);
    expect((await database.getClient(_name))?['user_id'], _userId);
  });
}
