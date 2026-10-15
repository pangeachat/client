import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/client_manager.dart';

/// The SDK announces `softLoggedOut` while it renews an access token and
/// `loggedIn` when the renewal lands. The session never ended, so the app's
/// login listener must not tear the account down, rebuild it or navigate for
/// either (#9304, session-lifetime.instructions.md).
void main() {
  List<bool> renewals(LoginState? initial, List<LoginState> states) {
    final filter = TokenRenewalFilter(initial);
    return states.map(filter.isRenewal).toList();
  }

  test('a renewal starting and landing is not a login change', () {
    expect(
      renewals(LoginState.loggedIn, [
        LoginState.softLoggedOut,
        LoginState.loggedIn,
      ]),
      [true, true],
    );
  });

  test('offline, every retry of a renewal is still a renewal', () {
    // The SDK re-announces softLoggedOut on each sync retry while the
    // server is unreachable; each one used to send the learner to the map.
    expect(
      renewals(LoginState.loggedIn, [
        LoginState.softLoggedOut,
        LoginState.softLoggedOut,
        LoginState.softLoggedOut,
        LoginState.loggedIn,
      ]),
      [true, true, true, true],
    );
  });

  test('a renewal already under way when the listener subscribes', () {
    // Startup renewal outlasting its wait lands after the app is on screen.
    expect(renewals(LoginState.softLoggedOut, [LoginState.loggedIn]), [true]);
  });

  test('a rejected renewal is a real sign-out, and the next login is real', () {
    expect(
      renewals(LoginState.loggedIn, [
        LoginState.softLoggedOut,
        LoginState.loggedOut,
        LoginState.loggedIn,
      ]),
      [true, false, false],
    );
  });

  test('a fresh login and a plain sign-out are login changes', () {
    expect(renewals(null, [LoginState.loggedIn]), [false]);
    expect(renewals(LoginState.loggedIn, [LoginState.loggedOut]), [false]);
  });
}
