import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/bot/bot_options_model.dart';
import 'package:fluffychat/features/bot/bot_room_extension.dart';

/// CLIENT-EQ6 / #9104: the profile-update fan-out kept writing bot options
/// after the learner signed out. On a signed-out client the SDK's permission
/// read (`client.userID!`) and the state write (`bearerToken!`) both throw,
/// and `setBotOptions` retried the write twice more, reporting each attempt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'setBotOptions on a signed-out client completes without throwing',
    () async {
      // Never logged in: userID and bearerToken are null and isLogged() is
      // false — the shape an account is in once sign-out has cleared it.
      final client = Client(
        'signedout',
        httpClient: FakeMatrixApi(),
        database: await MatrixSdkDatabase.init(
          'test',
          database: await databaseFactoryFfi.openDatabase(':memory:'),
          sqfliteFactory: databaseFactoryFfi,
        ),
      );
      addTearDown(client.dispose);
      final room = Room(
        id: '!bot:fakeServer.notExisting',
        client: client,
        membership: Membership.join,
      );

      await expectLater(
        room.setBotOptions(BotOptionsModel(targetLanguage: 'es')),
        completes,
      );
    },
  );
}
