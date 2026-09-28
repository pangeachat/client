import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';

/// The SDK announces `softLoggedOut` while it renews an access token and
/// `loggedIn` when the renewal lands. The session never ended, so neither
/// transition may tear the account down or rebuild it (#9304,
/// session-lifetime.instructions.md). Tearing down on `softLoggedOut` used to
/// clear the learner's state on every renewal, and after an offline renewal
/// left it cleared until the server came back.
void main() {
  bool renewal(LoginState? previous, LoginState state) =>
      PangeaController.isTokenRenewal(previous, state);

  test('a renewal starting or landing is not a login change', () {
    expect(renewal(LoginState.loggedIn, LoginState.softLoggedOut), isTrue);
    expect(renewal(LoginState.softLoggedOut, LoginState.loggedIn), isTrue);
  });

  test('a real login or sign-out still is', () {
    expect(renewal(null, LoginState.loggedIn), isFalse);
    expect(renewal(LoginState.loggedOut, LoginState.loggedIn), isFalse);
    expect(renewal(LoginState.loggedIn, LoginState.loggedOut), isFalse);
    // The server rejected the renewal: the SDK signed out.
    expect(renewal(LoginState.softLoggedOut, LoginState.loggedOut), isFalse);
  });
}
