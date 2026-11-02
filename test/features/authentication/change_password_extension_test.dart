import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/authentication/change_password_extension.dart';
import '../../utils/test_client.dart';

void main() {
  test(
    'a password change signs in again on the same device and keeps the new tokens',
    () async {
      final client = await prepareTestClient(loggedIn: true);
      final deviceId = client.deviceID;
      final api = FakeMatrixApi.currentApi!;

      Map<String, Object?>? loginBody;
      api.api['POST']!['/client/v3/login'] = (req) {
        loginBody = jsonDecode(req as String) as Map<String, Object?>;
        return {
          'user_id': client.userID,
          'device_id': deviceId,
          'access_token': 'renewed_access_token',
          'refresh_token': 'renewed_refresh_token',
          'expires_in_ms': 86400000,
        };
      };

      await client.changePasswordKeepingSession('newPass', oldPassword: 'old');

      expect(loginBody?['password'], 'newPass');
      expect(loginBody?['device_id'], deviceId);
      expect(client.deviceID, deviceId);
      expect(client.accessToken, 'renewed_access_token');
      final stored = await client.database.getClient(client.clientName);
      expect(stored?['token'], 'renewed_access_token');
      expect(stored?['refresh_token'], 'renewed_refresh_token');
    },
  );

  test('a failed password change does not sign in again', () async {
    final client = await prepareTestClient(loggedIn: true);
    final tokenBefore = client.accessToken;
    final api = FakeMatrixApi.currentApi!;

    var loginCalled = false;
    api.api['POST']!['/client/v3/account/password'] = (req) =>
        throw MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'Invalid password',
        });
    api.api['POST']!['/client/v3/login'] = (req) {
      loginCalled = true;
      return {};
    };

    await expectLater(
      client.changePasswordKeepingSession('newPass', oldPassword: 'wrong'),
      throwsA(isA<MatrixException>()),
    );
    expect(loginCalled, isFalse);
    expect(client.accessToken, tokenBefore);
  });
}
