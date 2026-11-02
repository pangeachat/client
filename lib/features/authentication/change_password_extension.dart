import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

extension ChangePasswordExtension on Client {
  /// Changes the password, signing out every other session, and keeps this
  /// one working.
  ///
  /// Synapse's password change deletes all of the user's refresh tokens,
  /// including this session's, and with it this session's access token. The
  /// token keeps working only from Synapse's cache, so the next refresh or
  /// re-authentication fails and the learner is signed out (ansible#191).
  /// Signing in again with the new password on this device's ID gives the
  /// session a fresh token pair without a new device, so its encryption keys
  /// carry over.
  Future<void> changePasswordKeepingSession(
    String newPassword, {
    required String oldPassword,
  }) async {
    await changePassword(newPassword, oldPassword: oldPassword);

    final userId = userID;
    final deviceId = deviceID;
    final homeserverUrl = homeserver;
    if (userId == null || deviceId == null || homeserverUrl == null) {
      ErrorHandler.logError(
        e: 'Password changed on a client with no session to renew',
        data: {
          'hasUserId': userId != null,
          'hasDeviceId': deviceId != null,
          'hasHomeserver': homeserverUrl != null,
        },
      );
      return;
    }

    try {
      // A bare MatrixApi, because Client.login re-initialises the running
      // client; only the tokens should change.
      final response =
          await MatrixApi(
            homeserver: homeserverUrl,
            httpClient: httpClient,
          ).login(
            LoginType.mLoginPassword,
            identifier: AuthenticationUserIdentifier(user: userId),
            password: newPassword,
            deviceId: deviceId,
            refreshToken: onSoftLogout != null,
          );
      final expiresInMs = response.expiresInMs;
      accessToken = response.accessToken;
      await database.updateClient(
        homeserverUrl.toString(),
        response.accessToken,
        expiresInMs == null
            ? null
            : DateTime.now().add(Duration(milliseconds: expiresInMs)),
        response.refreshToken,
        userId,
        deviceId,
        deviceName,
        prevBatch,
        encryption?.pickledOlmAccount,
      );
    } catch (e, s) {
      // The password did change, so this is not the caller's failure to
      // show; the session ends at its next refresh.
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'step': 'renewSessionAfterPasswordChange'},
      );
    }
  }
}
