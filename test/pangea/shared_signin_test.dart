import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/shared_signin/shared_signin.dart';

const _state = '0123456789abcdef0123456789abcdef';
final _dash = Uri.parse('https://admin.example.test');
const _bff = 'https://api.example.test';
final _dashFlag = '$dashboardSignedInFlag=${Uri.encodeComponent(_dash.origin)}';

void main() {
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

    test('are read by exact name', () {
      expect(
        readCookie('a=1; $_dashFlag', dashboardSignedInFlag),
        _dash.origin,
      );
      expect(readCookie('x$_dashFlag', dashboardSignedInFlag), isNull);
      expect(readCookie(null, dashboardSignedInFlag), isNull);
    });
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
