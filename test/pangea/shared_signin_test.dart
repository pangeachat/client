import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/shared_signin/shared_signin.dart';

const _state = '0123456789abcdef0123456789abcdef';

final _dash = Uri.parse('https://admin.example.test');
const _bff = 'https://api.example.test';
final _dashFlag = '$dashboardSignedInFlag=${Uri.encodeComponent(_dash.origin)}';

void main() {
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
      List<Object>? routine,
    }) => askDashboardForLoginToken(
      hasSession: hasSession,
      cookies: cookies ?? _dashFlag,
      dashboard: dashboard ?? _dash,
      teacherBffApi: bff,
      post: post ?? (_) async => '{"login_token":"tok"}',
      onError: (e, _) => errors?.add(e),
      onRoutine: (_, e) => routine?.add(e ?? 'none'),
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
      'an API that is down is routine (info); a confused answer is an error',
      () async {
        final errors = <Object>[];
        final routine = <Object>[];
        expect(
          await ask(
            post: (_) async => throw Exception('down'),
            errors: errors,
            routine: routine,
          ),
          isNull,
        );
        expect(routine, hasLength(1));
        expect(errors, isEmpty);
        expect(
          await ask(
            post: (_) async => 'not json',
            errors: errors,
            routine: routine,
          ),
          isNull,
        );
        expect(
          await ask(post: (_) async => '[]', errors: errors, routine: routine),
          isNull,
        );
        expect(errors, hasLength(2));
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
        onRoutine: (_, e) => errors.add(e ?? 'none'),
        timeout: const Duration(milliseconds: 20),
      );
      expect(token, isNull);
      expect(errors.single, isA<TimeoutException>());
      expect(dashboardAskTimeout, const Duration(seconds: 5));
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
  final List<String> routine = [];
  @override
  void onRoutine(String message, Object? error) => routine.add(message);
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

    test('the API down: the normal sign-in, logged as routine', () async {
      final host = FakeHost()
        ..cookies = _dashFlag
        ..postAnswer = (_) async => throw Exception('down');
      expect(await signInFromDashboard(host), isFalse);
      expect(host.logins, isEmpty);
      expect(host.errors, isEmpty);
      expect(host.routine, hasLength(1));
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

  group('signing out of both: the signed-out marker', () {
    final marker = '$signedOutMarker=${Uri.encodeComponent(_dash.origin)}';

    test(
      'the app\'s sign-out sets it on the shared domain, naming the dashboard',
      () {
        final host = FakeHost();
        markSignedOutOfBoth(host, true);
        expect(
          host.written.single,
          '$marker; Path=/; SameSite=Lax; Max-Age=31536000; Domain=example.test; Secure',
        );
        markSignedOutOfBoth(host, false);
        expect(host.written.last, startsWith('$signedOutMarker=;'));
        expect(host.written.last, contains('1970'));
      },
    );

    test(
      'another environment\'s marker neither counts nor hides this one\'s',
      () {
        final prod =
            '$signedOutMarker=${Uri.encodeComponent('https://admin.pangea.chat')}';
        expect(signedOutOfBoth(prod, _dash), isFalse);
        expect(signedOutOfBoth('$prod; $marker', _dash), isTrue);
        expect(signedOutOfBoth(marker, null), isFalse);
      },
    );

    test(
      'at boot, a session found while it is set is signed out here, the normal way',
      () async {
        final host = FakeHost()
          ..session = true
          ..cookies = '$_dashFlag; $marker';
        expect(await signInFromDashboard(host), isFalse);
        expect(host.signOuts, 1);
        expect(host.session, isFalse);
        expect(host.posts, isEmpty);
        expect(host.written.last, startsWith('$appSignedInFlag=;'));
      },
    );

    test(
      'while it is set, a signed-out app never asks the dashboard',
      () async {
        final host = FakeHost()..cookies = '$_dashFlag; $marker';
        expect(await signInFromDashboard(host), isFalse);
        expect(host.posts, isEmpty);
        expect(host.signOuts, 0);
      },
    );

    test(
      'while it is set, the dashboard\'s request is answered none',
      () async {
        final host = FakeHost()
          ..session = true
          ..cookies = marker;
        expect(await answerDashboard(host, _state), isTrue);
        expect(host.left.single, dashboardAnswerUrl(_dash, _state));
      },
    );

    test(
      'a failed sign-out here is reported and the flag still cleared',
      () async {
        final host = FakeHost()
          ..session = true
          ..cookies = marker
          ..signOutError = Exception('network');
        await signInFromDashboard(host);
        expect(host.errors, hasLength(1));
        expect(host.written.last, startsWith('$appSignedInFlag=;'));
      },
    );
  });

  group('routine outcomes are not errors', () {
    test("Synapse's one-a-minute limit on a mint is routine", () async {
      final host = FakeHost()
        ..session = true
        ..mintError = MatrixException.fromJson({
          'errcode': 'M_LIMIT_EXCEEDED',
          'error': 'Too Many Requests',
        });
      await answerDashboard(host, _state);
      expect(host.errors, isEmpty);
      expect(host.routine, hasLength(1));
    });

    test(
      'a used or expired token is routine; anything else an error',
      () async {
        final used = FakeHost()
          ..cookies = _dashFlag
          ..loginError = MatrixException.fromJson({
            'errcode': 'M_FORBIDDEN',
            'error': 'Invalid login token',
          });
        await signInFromDashboard(used);
        expect(used.errors, isEmpty);
        expect(used.routine, hasLength(1));
        final broken = FakeHost()
          ..cookies = _dashFlag
          ..loginError = StateError('bug');
        await signInFromDashboard(broken);
        expect(broken.errors, hasLength(1));
      },
    );
  });
}
