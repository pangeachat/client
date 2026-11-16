import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/shared_signin/shared_signin.dart';

const _state = '0123456789abcdef0123456789abcdef';
final _dash = Uri.parse('https://admin.example.test');
const _bff = 'https://api.example.test';
final _dashFlag = '$dashboardSignedInFlag=${Uri.encodeComponent(_dash.origin)}';

void main() {
  signOutTests();
  flowTests();
  group('the dashboard', () {
    test('must be https, or http on this machine', () {
      expect(
        dashboardBase('https://admin.example.test/').toString(),
        'https://admin.example.test',
      );
      expect(
        dashboardBase('http://localhost:3000').toString(),
        'http://localhost:3000',
      );
      for (final bad in [
        null,
        '',
        'http://admin.example.test',
        'javascript:alert(1)',
        'https://u@admin.example.test',
        'https://admin.example.test/?x=1',
        'https://admin.example.test/#x',
      ]) {
        expect(dashboardBase(bad), isNull, reason: bad);
      }
    });

    test("is answered only at its fixed page, in the fragment", () {
      expect(
        dashboardAnswerUrl(_dash, _state, loginToken: 'a+b&c'),
        'https://admin.example.test/auth/handoff/#loginToken=a%2Bb%26c&state=$_state',
      );
      expect(
        dashboardAnswerUrl(_dash, _state),
        'https://admin.example.test/auth/handoff/#handoff=none&state=$_state',
      );
    });

    test("asks with exactly a well-formed state", () {
      expect(dashboardRequestState('state=$_state'), _state);
      for (final bad in [
        null,
        '',
        'state=short',
        'state=$_state&loginToken=x',
        'loginToken=x&state=$_state',
      ]) {
        expect(dashboardRequestState(bad), isNull, reason: bad);
      }
    });
  });

  group('the signed-in flags', () {
    test('share the parent domain two hosts have in common', () {
      expect(
        sharedCookieDomain(
          'app.staging.pangea.chat',
          'admin.staging.pangea.chat',
        ),
        'staging.pangea.chat',
      );
      expect(sharedCookieDomain('localhost', 'localhost'), '');
      expect(sharedCookieDomain('app.a.com', 'admin.b.com'), isNull);
      expect(sharedCookieDomain('a.com', 'b.com'), isNull);
    });

    test("the app's flag names its origin and is cleared on sign-out", () {
      final app = Uri.parse('https://app.example.test/some/page');
      expect(
        appFlagCookie(signedIn: true, app: app, dashboard: _dash),
        '$appSignedInFlag=${Uri.encodeComponent('https://app.example.test')}; '
        'Path=/; SameSite=Lax; Max-Age=2592000; Domain=example.test; Secure',
      );
      expect(
        appFlagCookie(signedIn: false, app: app, dashboard: _dash),
        contains('Expires=Thu, 01 Jan 1970 00:00:00 GMT'),
      );
      expect(
        appFlagCookie(
          signedIn: true,
          app: Uri.parse('http://localhost:8090/'),
          dashboard: Uri.parse('http://localhost:3000'),
        ),
        '$appSignedInFlag=${Uri.encodeComponent('http://localhost:8090')}; '
        'Path=/; SameSite=Lax; Max-Age=2592000',
      );
      expect(
        appFlagCookie(
          signedIn: true,
          app: Uri.parse('https://app.other.com'),
          dashboard: _dash,
        ),
        isNull,
      );
    });

    test('are read by exact name, every value of it', () {
      expect(cookieValues('a=1; $_dashFlag', dashboardSignedInFlag), [
        _dash.origin,
      ]);
      expect(cookieValues('x$_dashFlag', dashboardSignedInFlag), isEmpty);
      expect(cookieValues(null, dashboardSignedInFlag), isEmpty);
    });

    test(
      "another environment's flag under the same name never hides this one's",
      () {
        // Prod's parent-domain cookie reaches staging hosts too.
        final prod =
            '$dashboardSignedInFlag=${Uri.encodeComponent('https://admin.pangea.chat')}';
        expect(dashboardSignedIn('$prod; $_dashFlag', _dash), isTrue);
        expect(dashboardSignedIn(prod, _dash), isFalse);
        expect(
          signOutRequested(
            'nonce=${'a' * 32}',
            '$signOutCookie=${'b' * 32}; $signOutCookie=${'a' * 32}',
          ),
          isTrue,
        );
      },
    );
  });

  group("asking the dashboard's API for a sign-in", () {
    Future<String?> ask({
      bool hasSession = false,
      String? cookies,
      Uri? dashboard,
      String bff = _bff,
      Future<String?> Function(Uri)? post,
      List<Object>? errors,
    }) => askDashboardForLoginToken(
      hasSession: hasSession,
      cookies: cookies ?? _dashFlag,
      dashboard: dashboard ?? _dash,
      teacherBffApi: bff,
      post: post ?? (_) async => '{"login_token":"tok"}',
      onError: (e, _) => errors?.add(e),
    );

    test('a signed-out app with the dashboard flag gets the token', () async {
      Uri? asked;
      final token = await ask(
        post: (url) async {
          asked = url;
          return '{"login_token":"tok"}';
        },
      );
      expect(token, 'tok');
      expect(asked.toString(), '$_bff/api/auth/handoff/app');
    });

    test(
      'never asks with a session, without the flag, or unconfigured',
      () async {
        var calls = 0;
        Future<String?> counted(Uri _) async {
          calls++;
          return '{"login_token":"tok"}';
        }

        expect(await ask(hasSession: true, post: counted), isNull);
        expect(await ask(cookies: 'other=1', post: counted), isNull);
        expect(
          await ask(
            cookies:
                '$dashboardSignedInFlag=${Uri.encodeComponent('https://elsewhere.test')}',
            post: counted,
          ),
          isNull,
        );
        expect(await ask(bff: '', post: counted), isNull);
        expect(calls, 0);
      },
    );

    test('no session there: the normal sign-in', () async {
      expect(await ask(post: (_) async => '{"login_token":null}'), isNull);
    });

    test(
      'an API that is down, slow or confused: the normal sign-in, and it is told',
      () async {
        final errors = <Object>[];
        expect(
          await ask(post: (_) async => throw Exception('down'), errors: errors),
          isNull,
        );
        expect(
          await ask(post: (_) async => 'not json', errors: errors),
          isNull,
        );
        expect(await ask(post: (_) async => '[]', errors: errors), isNull);
        expect(errors, hasLength(3));
      },
    );

    test('a slow API gives up after the timeout: the normal sign-in', () async {
      final errors = <Object>[];
      final token = await askDashboardForLoginToken(
        hasSession: false,
        cookies: _dashFlag,
        dashboard: _dash,
        teacherBffApi: _bff,
        post: (_) => Completer<String?>().future,
        onError: (e, _) => errors.add(e),
        timeout: const Duration(milliseconds: 20),
      );
      expect(token, isNull);
      expect(errors.single, isA<TimeoutException>());
      expect(dashboardAskTimeout, const Duration(seconds: 5));
    });
  });
}

void signOutTests() {
  group('signing out of both (owner, 2026-11-16)', () {
    const nonce = '0123456789abcdef0123456789abcdef';

    test("the dashboard's sign-out page, with the nonce in the fragment", () {
      expect(
        dashboardSignOutUrl(_dash, nonce),
        'https://admin.example.test/auth/signout/#nonce=$nonce',
      );
      expect(newNonce(), matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('the nonce also sits in a short-lived shared-domain cookie', () {
      expect(
        sharedCookie(
          name: signOutCookie,
          value: nonce,
          maxAge: 120,
          app: Uri.parse('https://app.example.test/'),
          dashboard: _dash,
        ),
        '$signOutCookie=$nonce; Path=/; SameSite=Lax; Max-Age=120; '
        'Domain=example.test; Secure',
      );
      expect(
        sharedCookie(
          name: signOutCookie,
          value: null,
          maxAge: 120,
          app: Uri.parse('https://app.example.test/'),
          dashboard: _dash,
        ),
        contains('Expires=Thu, 01 Jan 1970 00:00:00 GMT'),
      );
    });

    test("the dashboard's request is honoured only with the nonce it set", () {
      expect(signOutRequested('nonce=$nonce', '$signOutCookie=$nonce'), isTrue);
      expect(signOutRequested('nonce=$nonce', 'other=1'), isFalse);
      expect(
        signOutRequested('nonce=$nonce', '$signOutCookie=${'f' * 32}'),
        isFalse,
      );
      expect(signOutRequested('nonce=short', '$signOutCookie=short'), isFalse);
      expect(signOutRequested(null, '$signOutCookie=$nonce'), isFalse);
    });

    test('the dashboard is signed out too only when it is signed in here', () {
      expect(dashboardSignedIn(_dashFlag, _dash), isTrue);
      expect(dashboardSignedIn('', _dash), isFalse);
      expect(dashboardSignedIn(_dashFlag, null), isFalse);
    });
  });
}

class FakeHost implements SharedSignInHost {
  @override
  Uri app = Uri.parse('https://app.example.test/');
  @override
  Uri? dashboard = _dash;
  @override
  String teacherBffApi = _bff;
  String cookies = '';
  final List<String> written = [];
  bool session = false;
  final List<Uri> posts = [];
  Future<String?> Function(Uri url) postAnswer = (_) async =>
      '{"login_token":"tok"}';
  final List<String> logins = [];
  Object? loginError;
  Object? mintError;
  Object? signOutError;
  int signOuts = 0;
  int worlds = 0;
  final List<String> left = [];
  final List<Object> errors = [];

  @override
  String? readCookies() => cookies;
  @override
  void writeCookie(String cookie) => written.add(cookie);
  @override
  bool hasSession() => session;
  @override
  Future<void> settled() async {}
  @override
  Future<String?> credentialedPost(Uri url) {
    posts.add(url);
    return postAnswer(url);
  }

  @override
  Future<void> loginWithToken(String loginToken) async {
    if (loginError != null) throw loginError!;
    logins.add(loginToken);
    session = true;
  }

  @override
  Future<String> mintLoginToken() async {
    if (mintError != null) throw mintError!;
    return 'minted';
  }

  @override
  Future<void> signOutHere() async {
    signOuts++;
    if (signOutError != null) throw signOutError!;
    session = false;
  }

  @override
  void goToWorld() => worlds++;
  @override
  void leaveFor(String url) => left.add(url);
  @override
  void onError(Object error, StackTrace stackTrace) => errors.add(error);
}

void flowTests() {
  const nonce = '0123456789abcdef0123456789abcdef';

  group('signing in from the dashboard at boot', () {
    test(
      'signed out with the dashboard flag: signs in, then opens /',
      () async {
        final host = FakeHost()..cookies = _dashFlag;
        expect(await signInFromDashboard(host), isTrue);
        expect(host.logins, ['tok']);
        expect(host.worlds, 1);
        expect(host.posts.single.toString(), '$_bff/api/auth/handoff/app');
        expect(host.written.first, startsWith('$appSignedInFlag=;'));
      },
    );

    test('already signed in: publishes the flag and asks nothing', () async {
      final host = FakeHost()
        ..cookies = _dashFlag
        ..session = true;
      expect(await signInFromDashboard(host), isFalse);
      expect(host.posts, isEmpty);
      expect(host.written.single, contains('Max-Age=2592000'));
    });

    test('a refused token: the normal sign-in, and it is reported', () async {
      final host = FakeHost()
        ..cookies = _dashFlag
        ..loginError = Exception('M_FORBIDDEN');
      expect(await signInFromDashboard(host), isFalse);
      expect(host.worlds, 0);
      expect(host.errors, hasLength(1));
    });

    test('the API down: the normal sign-in, reported', () async {
      final host = FakeHost()
        ..cookies = _dashFlag
        ..postAnswer = (_) async => throw Exception('down');
      expect(await signInFromDashboard(host), isFalse);
      expect(host.logins, isEmpty);
      expect(host.errors, hasLength(1));
    });
  });

  group("answering the dashboard's request", () {
    test('signed in: a token, only to the dashboard\'s fixed page', () async {
      final host = FakeHost()..session = true;
      expect(await answerDashboard(host, nonce), isTrue);
      expect(
        host.left.single,
        dashboardAnswerUrl(_dash, nonce, loginToken: 'minted'),
      );
    });

    test('signed out, or no token to mint: none', () async {
      final out = FakeHost();
      await answerDashboard(out, nonce);
      expect(out.left.single, dashboardAnswerUrl(_dash, nonce));
      final limited = FakeHost()
        ..session = true
        ..mintError = Exception('429');
      await answerDashboard(limited, nonce);
      expect(limited.left.single, dashboardAnswerUrl(_dash, nonce));
      expect(limited.errors, hasLength(1));
    });

    test('no request or no dashboard: nothing to answer', () async {
      expect(await answerDashboard(FakeHost(), null), isFalse);
      expect(
        await answerDashboard(FakeHost()..dashboard = null, nonce),
        isFalse,
      );
    });
  });

  group("the app's sign-out signs this browser out of the dashboard", () {
    test("through the dashboard's API, whatever its pages are doing", () async {
      final host = FakeHost()..cookies = _dashFlag;
      await signOutDashboardToo(host);
      expect(host.posts.single.toString(), '$_bff/api/auth/logout');
      expect(host.written.single, startsWith('$dashboardSignedInFlag=;'));
      expect(host.written.single, contains('1970'));
    });

    test(
      'the API down: the flag is still gone, so nothing signs back in',
      () async {
        final host = FakeHost()
          ..cookies = _dashFlag
          ..postAnswer = (_) async => throw Exception('down');
        await signOutDashboardToo(host);
        expect(host.written.single, startsWith('$dashboardSignedInFlag=;'));
        expect(host.errors, hasLength(1));
        // Reopened: no flag, so no hand-off.
        final reopened = FakeHost();
        expect(await signInFromDashboard(reopened), isFalse);
        expect(reopened.posts, isEmpty);
      },
    );

    test('the dashboard not signed in here: nothing to do', () async {
      final host = FakeHost();
      await signOutDashboardToo(host);
      expect(host.posts, isEmpty);
      expect(host.written, isEmpty);
    });
  });

  group("answering the dashboard's sign-out", () {
    test(
      'with its nonce: signs out the normal way, clears the flag, then back',
      () async {
        final host = FakeHost()
          ..session = true
          ..cookies = '$signOutCookie=$nonce';
        expect(await answerSignOut(host, 'nonce=$nonce'), isTrue);
        expect(host.signOuts, 1);
        expect(host.written.first, startsWith('$signOutCookie=;'));
        expect(host.written.last, startsWith('$appSignedInFlag=;'));
        expect(host.left.single, '$_dash/login/');
      },
    );

    test(
      'a link from elsewhere (no matching nonce) signs nobody out',
      () async {
        final host = FakeHost()..session = true;
        expect(await answerSignOut(host, 'nonce=$nonce'), isFalse);
        expect(host.signOuts, 0);
        expect(host.left, isEmpty);
        expect(host.written.single, startsWith('$signOutCookie=;'));
      },
    );

    test(
      'a failed sign-out still returns to the dashboard, reported',
      () async {
        final host = FakeHost()
          ..session = true
          ..cookies = '$signOutCookie=$nonce'
          ..signOutError = Exception('network');
        expect(await answerSignOut(host, 'nonce=$nonce'), isTrue);
        expect(host.errors, hasLength(1));
        expect(host.left.single, '$_dash/login/');
      },
    );

    test('no dashboard configured: nothing', () async {
      expect(
        await answerSignOut(FakeHost()..dashboard = null, 'nonce=$nonce'),
        isFalse,
      );
    });
  });
}
