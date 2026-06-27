import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/config/dev_login.dart';

void main() {
  group('shouldDevLogin — safety gates', () {
    // Happy path: debug build, opted-in, creds present, local homeserver. Each
    // test below flips exactly one input to assert the gate. The "already logged
    // in" skip is NOT part of this pure gate — maybeDevLogin checks the live
    // client's restored login state at runtime (after the session settles).
    bool gate({
      bool isDebug = true,
      bool requested = true,
      String? username = 'learner',
      String? password = 'learnerpass',
      String loginHost = 'localhost',
    }) => shouldDevLogin(
      isDebug: isDebug,
      requested: requested,
      username: username,
      password: password,
      loginHost: loginHost,
    );

    test('proceeds in the happy path', () {
      expect(gate(), isTrue);
    });

    test('never runs in a release build', () {
      expect(gate(isDebug: false), isFalse);
    });

    test('does nothing without the ?devlogin=1 opt-in', () {
      expect(gate(requested: false), isFalse);
    });

    test('skips when credentials are missing', () {
      expect(gate(username: null), isFalse);
      expect(gate(username: ''), isFalse);
      expect(gate(password: null), isFalse);
      expect(gate(password: ''), isFalse);
    });

    test('refuses any non-localhost, non-staging login host', () {
      for (final host in [
        'pangea.chat', // production apex
        'matrix.pangea.chat', // production
        'app.pangea.chat', // production alias
        'pangea.chat.', // trailing-dot FQDN form
        'local.pangea.chat', // a server name, not the connection host
        'evil-staging.pangea.chat', // suffix-looking, not a *.staging subdomain
        'staging.pangea.chat.evil.test', // staging label under another domain
        '10.0.0.5', // raw IP
        '', // empty / unparseable host
      ]) {
        expect(gate(loginHost: host), isFalse, reason: host);
      }
    });

    test('allows only localhost and staging login hosts', () {
      for (final host in [
        'localhost',
        '127.0.0.1',
        'staging.pangea.chat',
        'matrix.staging.pangea.chat',
        'STAGING.PANGEA.CHAT', // case-insensitive
      ]) {
        expect(gate(loginHost: host), isTrue, reason: host);
      }
    });
  });

  group('devLoginRequested — URL parsing', () {
    test('true for a top-level ?devlogin=1', () {
      expect(
        devLoginRequested(Uri.parse('http://localhost:8090/?devlogin=1')),
        isTrue,
      );
    });

    test('true for the param inside a hash route', () {
      expect(
        devLoginRequested(Uri.parse('http://localhost:8090/#/?devlogin=1')),
        isTrue,
      );
      expect(
        devLoginRequested(
          Uri.parse('http://localhost:8090/#/world?devlogin=1'),
        ),
        isTrue,
      );
    });

    test('false without the param', () {
      expect(devLoginRequested(Uri.parse('http://localhost:8090/')), isFalse);
      expect(
        devLoginRequested(Uri.parse('http://localhost:8090/#/world')),
        isFalse,
      );
    });

    test('false for a non-1 value', () {
      expect(
        devLoginRequested(Uri.parse('http://localhost:8090/?devlogin=0')),
        isFalse,
      );
    });
  });
}
