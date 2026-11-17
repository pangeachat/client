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
        appFlagCookie(signedIn: true, app: app, dashboard: _dash, began: 7),
        '$appSignedInFlag=${Uri.encodeComponent('https://app.example.test|7')}; '
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
        '$appSignedInFlag=${Uri.encodeComponent('http://localhost:8090|0')}; '
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
  int? sessionStart;
  int clock = 5000;
  Set<String> accounts = {};
  final List<Uri> posts = [];
  Future<String?> Function(Uri url) postAnswer = (_) async =>
      '{"login_token":"tok"}';
  final List<String> logins = [];
  Object? loginError;
  Object? mintError;
  Object? signOutError;
  final List<Set<String>> signOuts = [];
  String? destination;
  final List<String> wentTo = [];
  int signIns = 0;
  final List<String> left = [];
  final List<Object> errors = [];
  final List<String> routine = [];

  @override
  String? readCookies() => cookies;
  @override
  void writeCookie(String cookie) => written.add(cookie);
  @override
  int? readSessionStart() => sessionStart;
  @override
  void writeSessionStart(int? ms) => sessionStart = ms;
  @override
  int now() => clock;
  @override
  List<String> liveAccounts() => accounts.toList();
  @override
  Future<void> signOut(Set<String> names) async {
    signOuts.add(names);
    if (signOutError != null) throw signOutError!;
    accounts.removeAll(names);
  }

  @override
  Future<String?> credentialedPost(Uri url) {
    posts.add(url);
    return postAnswer(url);
  }

  @override
  Future<void> loginWithToken(String loginToken) async {
    if (loginError != null) throw loginError!;
    logins.add(loginToken);
    // The guard consumes the kept link as soon as a sign-in lands.
    destination = null;
    accounts.add('handoff');
  }

  @override
  Future<String> mintLoginToken() async {
    if (mintError != null) throw mintError!;
    return 'minted';
  }

  @override
  String? keptDestination() => destination;
  @override
  void goTo(String location) => wentTo.add(location);
  @override
  void goToSignIn() => signIns++;
  @override
  void leaveFor(String url) => left.add(url);
  @override
  void onError(Object error, StackTrace stackTrace) => errors.add(error);
  @override
  void onRoutine(String message, Object? error) => routine.add(message);
}

String _stamp(String name, String origin, int ms) =>
    '$name=${Uri.encodeComponent('$origin|$ms')}';

void flowTests() {
  const state = _state;
  String dashAt(int ms) => _stamp(dashboardSignedInFlag, _dash.origin, ms);
  String outAt(int ms) => _stamp(signedOutMarker, _dash.origin, ms);

  group('signing in from the dashboard at start', () {
    test(
      'signed out, with a dashboard session: signs in, then opens the kept link',
      () async {
        final host = FakeHost()
          ..cookies = dashAt(100)
          ..destination = '/?left=session:abc';
        expect(await signInFromDashboard(host), isTrue);
        expect(host.logins, ['tok']);
        // Not `/`: the guard has already consumed the link by then.
        expect(host.wentTo, ['/?left=session:abc']);
        expect(host.posts.single.toString(), '$_bff/api/auth/handoff/app');
      },
    );

    test('with no kept link, opens the map', () async {
      final host = FakeHost()..cookies = dashAt(100);
      await signInFromDashboard(host);
      expect(host.wentTo, ['/']);
    });

    test(
      'already signed in: publishes when the session began and asks nothing',
      () async {
        final host = FakeHost()
          ..cookies = dashAt(100)
          ..accounts = {'a'}
          ..sessionStart = 42;
        expect(await signInFromDashboard(host), isFalse);
        expect(host.posts, isEmpty);
        expect(
          host.written.single,
          startsWith(
            '$appSignedInFlag=${Uri.encodeComponent('${host.app.origin}|42')};',
          ),
        );
      },
    );

    test(
      'a dashboard session that began before the latest sign-out is never asked',
      () async {
        final host = FakeHost()..cookies = '${dashAt(100)}; ${outAt(200)}';
        expect(await signInFromDashboard(host), isFalse);
        expect(host.posts, isEmpty);
        final fresh = FakeHost()..cookies = '${dashAt(300)}; ${outAt(200)}';
        expect(await signInFromDashboard(fresh), isTrue);
      },
    );

    test('the API down: the normal sign-in, logged as routine', () async {
      final host = FakeHost()
        ..cookies = dashAt(100)
        ..postAnswer = (_) async => throw Exception('down');
      expect(await signInFromDashboard(host), isFalse);
      expect(host.logins, isEmpty);
      expect(host.errors, isEmpty);
      expect(host.routine, hasLength(1));
    });
  });

  group("answering the dashboard's request", () {
    test("signed in: a token, only to the dashboard's fixed page", () async {
      final host = FakeHost()..accounts = {'a'};
      expect(await answerDashboard(host, state), isTrue);
      expect(
        host.left.single,
        dashboardAnswerUrl(_dash, state, loginToken: 'minted'),
      );
    });

    test('signed out, or no token to mint: none', () async {
      final out = FakeHost();
      await answerDashboard(out, state);
      expect(out.left.single, dashboardAnswerUrl(_dash, state));
      final failing = FakeHost()
        ..accounts = {'a'}
        ..mintError = Exception('boom');
      await answerDashboard(failing, state);
      expect(failing.left.single, dashboardAnswerUrl(_dash, state));
      expect(failing.errors, hasLength(1));
    });

    test('no request or no dashboard: nothing to answer', () async {
      expect(await answerDashboard(FakeHost(), null), isFalse);
      expect(
        await answerDashboard(FakeHost()..dashboard = null, state),
        isFalse,
      );
    });
  });

  group('signing out of both: the signed-out time', () {
    test(
      "the app's sign-out writes when, on the shared domain, naming the dashboard",
      () {
        final host = FakeHost()..clock = 1234;
        markSignedOutOfBoth(host);
        expect(
          host.written.single,
          '${outAt(1234)}; Path=/; SameSite=Lax; Max-Age=31536000; Domain=example.test; Secure',
        );
      },
    );

    test(
      "reads this dashboard's latest sign-out, never another environment's",
      () {
        final prod = _stamp(signedOutMarker, 'https://admin.pangea.chat', 900);
        expect(signedOutAt(prod, _dash), isNull);
        expect(signedOutAt('$prod; ${outAt(200)}; ${outAt(100)}', _dash), 200);
        expect(
          signedOutAt(
            '$signedOutMarker=${Uri.encodeComponent(_dash.origin)}',
            _dash,
          ),
          0,
        );
      },
    );

    test(
      'a session that began before the sign-out is signed out; one begun after it is kept',
      () {
        final before = FakeHost()
          ..cookies = outAt(200)
          ..accounts = {'a'}
          ..sessionStart = 100;
        expect(accountsToSignOut(before), {'a'});
        final after = FakeHost()
          ..cookies = outAt(200)
          ..accounts = {'a'}
          ..sessionStart = 300;
        expect(accountsToSignOut(after), isEmpty);
        final unknown = FakeHost()
          ..cookies = outAt(200)
          ..accounts = {'a'};
        expect(accountsToSignOut(unknown), {'a'});
        expect(accountsToSignOut(FakeHost()..accounts = {'a'}), isEmpty);
      },
    );

    test(
      'signing out the normal way forgets the session and opens the sign-in',
      () async {
        final host = FakeHost()
          ..accounts = {'a'}
          ..sessionStart = 100;
        await honourSignOut(host, {'a'});
        expect(host.signOuts.single, {'a'});
        expect(host.sessionStart, isNull);
        expect(host.signIns, 1);
        expect(host.written.last, startsWith('$appSignedInFlag=;'));
      },
    );

    test('a sign-in by hand while it ran is left alone', () async {
      final host = FakeHost()
        ..accounts = {'a', 'new'}
        ..sessionStart = 900;
      await honourSignOut(host, {'a'});
      expect(host.accounts, {'new'});
      expect(host.sessionStart, 900);
      expect(host.signIns, 0);
    });

    test('a failed sign-out is reported', () async {
      final host = FakeHost()
        ..accounts = {'a'}
        ..signOutError = Exception('network');
      await honourSignOut(host, {'a'});
      expect(host.errors, hasLength(1));
    });

    test(
      'a new session is stamped with when it began; a restored one keeps its stamp; none left forgets it',
      () {
        final fresh = FakeHost()
          ..accounts = {'a'}
          ..clock = 777;
        onSessionChange(fresh);
        expect(fresh.sessionStart, 777);
        final restored = FakeHost()
          ..accounts = {'a'}
          ..sessionStart = 5
          ..clock = 777;
        onSessionChange(restored);
        expect(restored.sessionStart, 5);
        final gone = FakeHost()..sessionStart = 5;
        onSessionChange(gone);
        expect(gone.sessionStart, isNull);
        expect(gone.written.last, startsWith('$appSignedInFlag=;'));
      },
    );

    test('a sign-in by hand after the sign-out is never undone by it', () {
      final host = FakeHost()
        ..cookies = outAt(200)
        ..clock = 300
        ..accounts = {'new'};
      onSessionChange(host);
      expect(accountsToSignOut(host), isEmpty);
    });
  });

  group('routine outcomes are not errors', () {
    test("Synapse's one-a-minute limit on a mint is routine", () async {
      final host = FakeHost()
        ..accounts = {'a'}
        ..mintError = MatrixException.fromJson({
          'errcode': 'M_LIMIT_EXCEEDED',
          'error': 'Too Many Requests',
        });
      await answerDashboard(host, state);
      expect(host.errors, isEmpty);
      expect(host.routine, hasLength(1));
    });

    test(
      'a used or expired token is routine; anything else an error',
      () async {
        final used = FakeHost()
          ..cookies = dashAt(100)
          ..loginError = MatrixException.fromJson({
            'errcode': 'M_FORBIDDEN',
            'error': 'Invalid login token',
          });
        await signInFromDashboard(used);
        expect(used.errors, isEmpty);
        expect(used.routine, hasLength(1));
        final broken = FakeHost()
          ..cookies = dashAt(100)
          ..loginError = StateError('bug');
        await signInFromDashboard(broken);
        expect(broken.errors, hasLength(1));
      },
    );
  });
}
